/**
 * zregexp - Modern Regular Expression Engine for Zig
 * C++ API Header
 *
 * Version: 1.0.0
 * License: MIT
 *
 * This header provides C++ bindings for the zregexp library.
 * For full documentation, see: https://github.com/yourusername/zregexp
 */

#ifndef ZREGEXP_HPP
#define ZREGEXP_HPP

#include "zregexp.h"
#include <string>
#include <vector>
#include <optional>
#include <stdexcept>
#include <memory>

namespace zregexp {

// =============================================================================
// Exceptions
// =============================================================================

/**
 * Base exception class for zregexp errors.
 */
class RegexError : public std::runtime_error {
public:
    explicit RegexError(const std::string& message)
        : std::runtime_error(message), error_code_(ZREGEXP_ERROR_UNKNOWN) {}

    RegexError(ZRegexError code, const std::string& message)
        : std::runtime_error(message), error_code_(code) {}

    ZRegexError code() const noexcept { return error_code_; }

private:
    ZRegexError error_code_;
};

/**
 * Exception thrown for syntax errors in regex patterns.
 */
class SyntaxError : public RegexError {
public:
    explicit SyntaxError(const std::string& message)
        : RegexError(ZREGEXP_ERROR_SYNTAX, message) {}
};

/**
 * Exception thrown when recursion limit is exceeded.
 */
class RecursionLimitError : public RegexError {
public:
    explicit RecursionLimitError(const std::string& message)
        : RegexError(ZREGEXP_ERROR_RECURSION_LIMIT, message) {}
};

// =============================================================================
// Options
// =============================================================================

/**
 * Compilation options for regular expressions.
 */
struct Options {
    bool case_insensitive = false;
    uint32_t max_recursion_depth = 1000;
    uint64_t max_steps = 1000000;

    /**
     * Create default options.
     */
    static Options defaults() {
        return Options{};
    }

    /**
     * Convert to C options structure.
     */
    ZRegexOptions to_c() const {
        ZRegexOptions opts = zregexp_default_options();
        opts.case_insensitive = case_insensitive;
        opts.max_recursion_depth = max_recursion_depth;
        opts.max_steps = max_steps;
        return opts;
    }
};

// =============================================================================
// Forward Declarations
// =============================================================================

class Match;
class MatchList;

// =============================================================================
// Regex Class
// =============================================================================

/**
 * Regular expression class with RAII semantics.
 *
 * @example
 *   auto re = Regex::compile("hello (\\w+)");
 *   auto match = re.find("hello world");
 *   if (match) {
 *       std::cout << "Match: " << match.slice() << std::endl;
 *   }
 */
class Regex {
public:
    /**
     * Compile a regular expression pattern.
     *
     * @param pattern The regex pattern string
     * @param options Compilation options
     * @return Compiled Regex object
     * @throws RegexError if compilation fails
     */
    static Regex compile(const std::string& pattern, const Options& options = Options::defaults()) {
        auto c_options = options.to_c();
        ZRegex* re = zregexp_compile(pattern.c_str(), &c_options);

        if (!re) {
            auto error = zregexp_last_error();
            throw RegexError(error, zregexp_error_message(error));
        }

        return Regex(re);
    }

    /**
     * Move constructor.
     */
    Regex(Regex&& other) noexcept : regex_(other.regex_) {
        other.regex_ = nullptr;
    }

    /**
     * Move assignment operator.
     */
    Regex& operator=(Regex&& other) noexcept {
        if (this != &other) {
            if (regex_) {
                zregexp_free(regex_);
            }
            regex_ = other.regex_;
            other.regex_ = nullptr;
        }
        return *this;
    }

    /**
     * Destructor.
     */
    ~Regex() {
        if (regex_) {
            zregexp_free(regex_);
        }
    }

    // Delete copy operations
    Regex(const Regex&) = delete;
    Regex& operator=(const Regex&) = delete;

    /**
     * Find the first match in the input string.
     *
     * @param input Input string to search
     * @return Match object if found, empty optional otherwise
     */
    std::optional<Match> find(const std::string& input) const;

    /**
     * Find all matches in the input string.
     *
     * @param input Input string to search
     * @return Vector of Match objects
     */
    std::vector<Match> findAll(const std::string& input) const;

    /**
     * Test if the pattern matches the input.
     *
     * @param input Input string to test
     * @return true if match found, false otherwise
     */
    bool isMatch(const std::string& input) const {
        return zregexp_is_match(regex_, input.c_str());
    }

    /**
     * Replace all matches with a replacement string.
     *
     * @param input Input string
     * @param replacement Replacement string
     * @return New string with replacements
     */
    std::string replace(const std::string& input, const std::string& replacement) const {
        char* result = zregexp_replace(regex_, input.c_str(), replacement.c_str());
        if (!result) {
            auto error = zregexp_last_error();
            throw RegexError(error, zregexp_error_message(error));
        }

        std::string str(result);
        zregexp_string_free(result);
        return str;
    }

    /**
     * Get the underlying C regex handle (for advanced use).
     */
    ZRegex* c_ptr() const { return regex_; }

private:
    explicit Regex(ZRegex* regex) : regex_(regex) {}

    ZRegex* regex_;
};

// =============================================================================
// Match Class
// =============================================================================

/**
 * Match result class with RAII semantics.
 */
class Match {
public:
    /**
     * Constructor from C match handle.
     */
    explicit Match(ZMatch* match, std::string input)
        : match_(match), input_(std::move(input)) {}

    /**
     * Move constructor.
     */
    Match(Match&& other) noexcept
        : match_(other.match_), input_(std::move(other.input_)) {
        other.match_ = nullptr;
    }

    /**
     * Move assignment operator.
     */
    Match& operator=(Match&& other) noexcept {
        if (this != &other) {
            if (match_) {
                zregexp_match_free(match_);
            }
            match_ = other.match_;
            input_ = std::move(other.input_);
            other.match_ = nullptr;
        }
        return *this;
    }

    /**
     * Destructor.
     */
    ~Match() {
        if (match_) {
            zregexp_match_free(match_);
        }
    }

    // Delete copy operations
    Match(const Match&) = delete;
    Match& operator=(const Match&) = delete;

    /**
     * Get the full matched text.
     */
    std::string slice() const {
        char* text = zregexp_match_slice(match_);
        if (!text) return std::string();
        std::string result(text);
        zregexp_string_free(text);
        return result;
    }

    /**
     * Get the start position of the match.
     */
    size_t start() const {
        return zregexp_match_start(match_);
    }

    /**
     * Get the end position of the match.
     */
    size_t end() const {
        return zregexp_match_end(match_);
    }

    /**
     * Get a capture group by index.
     *
     * @param group_index Group index (1-9 for \1-\9, 0 for full match)
     * @return Captured text if group participated, empty optional otherwise
     */
    std::optional<std::string> group(uint8_t group_index) const {
        char* text = zregexp_match_group(match_, group_index);
        if (text) {
            std::string result(text);
            zregexp_string_free(text);
            return result;
        }
        return std::nullopt;
    }

    /**
     * Get the underlying C match handle (for advanced use).
     */
    ZMatch* c_ptr() const { return match_; }

private:
    ZMatch* match_;
    std::string input_;
};

// =============================================================================
// Inline Implementations
// =============================================================================

inline std::optional<Match> Regex::find(const std::string& input) const {
    ZMatch* c_match = zregexp_find(regex_, input.c_str());
    if (c_match) {
        return Match(c_match, input);
    }
    return std::nullopt;
}

inline std::vector<Match> Regex::findAll(const std::string& input) const {
    std::vector<Match> matches;

    // Use a simple approach: repeatedly call find() with increasing offset
    size_t offset = 0;

    while (offset <= input.length()) {
        // Create a substring starting from offset
        std::string remaining = input.substr(offset);
        ZMatch* c_match = zregexp_find(regex_, remaining.c_str());

        if (!c_match) {
            // No more matches
            break;
        }

        // Get match end position (relative to substring)
        size_t local_end = zregexp_match_end(c_match);

        // Store the match with its substring
        matches.emplace_back(c_match, remaining);

        // Move offset past this match
        if (local_end == 0) {
            // Empty match, advance by 1 to avoid infinite loop
            offset += 1;
        } else {
            offset += local_end;
        }
    }

    return matches;
}

// =============================================================================
// Utility Functions
// =============================================================================

/**
 * Escape special regex characters in a string.
 *
 * @param input Input string
 * @return Escaped string
 */
inline std::string escape(const std::string& input) {
    char* result = zregexp_escape(input.c_str());
    if (!result) {
        return input;
    }

    std::string escaped(result);
    zregexp_string_free(result);
    return escaped;
}

/**
 * Test if a string is a valid regex pattern.
 *
 * @param pattern Pattern string
 * @return true if valid, false otherwise
 */
inline bool isValidPattern(const std::string& pattern) {
    return zregexp_is_valid_pattern(pattern.c_str());
}

/**
 * Get the library version.
 *
 * @return Version string
 */
inline std::string version() {
    return zregexp_version();
}

} // namespace zregexp

#endif /* ZREGEXP_HPP */
