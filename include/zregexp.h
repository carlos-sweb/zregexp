/**
 * zregexp - Modern Regular Expression Engine for Zig
 * C API Header
 *
 * Version: 1.0.0
 * License: MIT
 *
 * This header provides C bindings for the zregexp library.
 * For full documentation, see: https://github.com/yourusername/zregexp
 */

#ifndef ZREGEXP_H
#define ZREGEXP_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

/* =============================================================================
 * Version Information
 * ===========================================================================*/

#define ZREGEXP_VERSION_MAJOR 1
#define ZREGEXP_VERSION_MINOR 0
#define ZREGEXP_VERSION_PATCH 0
#define ZREGEXP_VERSION "1.0.0"

/**
 * Get the library version string.
 *
 * @return Version string (e.g., "1.0.0")
 */
const char* zregexp_version(void);

/* =============================================================================
 * Opaque Types
 * ===========================================================================*/

/**
 * Opaque handle to a compiled regular expression.
 */
typedef struct ZRegex ZRegex;

/**
 * Opaque handle to a match result.
 */
typedef struct ZMatch ZMatch;

/**
 * Opaque handle to a list of match results.
 */
typedef struct ZMatchList ZMatchList;

/* =============================================================================
 * Compilation Options
 * ===========================================================================*/

/**
 * Options for compiling a regular expression.
 */
typedef struct {
    /** Enable case-insensitive matching */
    bool case_insensitive;

    /** Maximum recursion depth (default: 1000) */
    uint32_t max_recursion_depth;

    /** Maximum execution steps (default: 1000000) */
    uint64_t max_steps;

    /** Reserved for future use */
    uint32_t reserved[4];
} ZRegexOptions;

/**
 * Get default options.
 *
 * @return Default options structure
 */
ZRegexOptions zregexp_default_options(void);

/* =============================================================================
 * Compilation and Destruction
 * ===========================================================================*/

/**
 * Compile a regular expression pattern.
 *
 * @param pattern The regex pattern string (null-terminated)
 * @param options Compilation options (NULL for defaults)
 * @return Compiled regex handle, or NULL on error
 *
 * @example
 *   ZRegex* re = zregexp_compile("hello (\\w+)", NULL);
 *   if (re) {
 *       // Use the regex...
 *       zregexp_free(re);
 *   }
 */
ZRegex* zregexp_compile(const char* pattern, const ZRegexOptions* options);

/**
 * Free a compiled regex.
 *
 * @param regex The regex to free (can be NULL)
 */
void zregexp_free(ZRegex* regex);

/* =============================================================================
 * Matching Functions
 * ===========================================================================*/

/**
 * Find the first match in the input string.
 *
 * @param regex Compiled regex
 * @param input Input string to search (null-terminated)
 * @return Match result, or NULL if no match found
 *
 * @example
 *   ZMatch* match = zregexp_find(re, "hello world");
 *   if (match) {
 *       printf("Match: %s\n", zregexp_match_slice(match));
 *       zregexp_match_free(match);
 *   }
 */
ZMatch* zregexp_find(ZRegex* regex, const char* input);

/**
 * Find all matches in the input string.
 *
 * @param regex Compiled regex
 * @param input Input string to search (null-terminated)
 * @return List of matches, or NULL on error
 *
 * @example
 *   ZMatchList* matches = zregexp_find_all(re, "one two three");
 *   size_t count = zregexp_match_list_count(matches);
 *   for (size_t i = 0; i < count; i++) {
 *       ZMatch* match = zregexp_match_list_get(matches, i);
 *       printf("Match %zu: %s\n", i, zregexp_match_slice(match));
 *   }
 *   zregexp_match_list_free(matches);
 */
ZMatchList* zregexp_find_all(ZRegex* regex, const char* input);

/**
 * Test if the pattern matches the input.
 *
 * @param regex Compiled regex
 * @param input Input string to test (null-terminated)
 * @return true if match found, false otherwise
 *
 * @example
 *   if (zregexp_is_match(re, "hello")) {
 *       printf("Pattern matches!\n");
 *   }
 */
bool zregexp_is_match(ZRegex* regex, const char* input);

/* =============================================================================
 * Match Result Functions
 * ===========================================================================*/

/**
 * Get the full matched text.
 *
 * @param match Match result
 * @return Matched text (null-terminated, must be freed with zregexp_string_free)
 */
char* zregexp_match_slice(ZMatch* match);

/**
 * Get the start position of the match.
 *
 * @param match Match result
 * @return Start position (byte offset)
 */
size_t zregexp_match_start(ZMatch* match);

/**
 * Get the end position of the match.
 *
 * @param match Match result
 * @return End position (byte offset, exclusive)
 */
size_t zregexp_match_end(ZMatch* match);

/**
 * Get a capture group by index.
 *
 * @param match Match result
 * @param group_index Group index (1-9 for \1-\9, 0 for full match)
 * @return Captured text (must be freed with zregexp_string_free), or NULL if group didn't participate
 *
 * @example
 *   char* group1 = zregexp_match_group(match, 1);
 *   if (group1) {
 *       printf("Group 1: %s\n", group1);
 *       zregexp_string_free(group1);
 *   }
 */
char* zregexp_match_group(ZMatch* match, uint8_t group_index);

/**
 * Free a match result.
 *
 * @param match The match to free (can be NULL)
 */
void zregexp_match_free(ZMatch* match);

/* =============================================================================
 * Match List Functions
 * ===========================================================================*/

/**
 * Get the number of matches in the list.
 *
 * @param list Match list
 * @return Number of matches
 */
size_t zregexp_match_list_count(ZMatchList* list);

/**
 * Get a match from the list by index.
 *
 * @param list Match list
 * @param index Match index (0-based)
 * @return Match result (owned by the list, don't free separately)
 */
ZMatch* zregexp_match_list_get(ZMatchList* list, size_t index);

/**
 * Free a match list and all its matches.
 *
 * @param list The match list to free (can be NULL)
 */
void zregexp_match_list_free(ZMatchList* list);

/* =============================================================================
 * String Replacement
 * ===========================================================================*/

/**
 * Replace all matches with a replacement string.
 *
 * @param regex Compiled regex
 * @param input Input string (null-terminated)
 * @param replacement Replacement string (null-terminated)
 * @return New string with replacements (must be freed with zregexp_string_free)
 *
 * @example
 *   char* result = zregexp_replace(re, "hello world", "hi");
 *   printf("Result: %s\n", result);
 *   zregexp_string_free(result);
 */
char* zregexp_replace(ZRegex* regex, const char* input, const char* replacement);

/**
 * Free a string returned by zregexp functions.
 *
 * @param str The string to free (can be NULL)
 */
void zregexp_string_free(char* str);

/* =============================================================================
 * Error Handling
 * ===========================================================================*/

/**
 * Error codes returned by zregexp functions.
 */
typedef enum {
    ZREGEXP_OK = 0,
    ZREGEXP_ERROR_SYNTAX,           /** Syntax error in pattern */
    ZREGEXP_ERROR_OUT_OF_MEMORY,    /** Memory allocation failed */
    ZREGEXP_ERROR_RECURSION_LIMIT,  /** Recursion depth limit exceeded */
    ZREGEXP_ERROR_STEP_LIMIT,       /** Execution step limit exceeded */
    ZREGEXP_ERROR_INVALID_GROUP,    /** Invalid group number */
    ZREGEXP_ERROR_UNMATCHED_PAREN,  /** Unmatched parenthesis */
    ZREGEXP_ERROR_INVALID_RANGE,    /** Invalid character range */
    ZREGEXP_ERROR_UNKNOWN           /** Unknown error */
} ZRegexError;

/**
 * Get the last error code.
 *
 * @return Last error code
 */
ZRegexError zregexp_last_error(void);

/**
 * Get a human-readable error message for an error code.
 *
 * @param error Error code
 * @return Error message (static string, don't free)
 */
const char* zregexp_error_message(ZRegexError error);

/**
 * Clear the last error.
 */
void zregexp_clear_error(void);

/* =============================================================================
 * Utility Functions
 * ===========================================================================*/

/**
 * Escape special regex characters in a string.
 *
 * @param input Input string (null-terminated)
 * @return Escaped string (must be freed with zregexp_string_free)
 *
 * @example
 *   char* escaped = zregexp_escape("hello.world");
 *   // Returns: "hello\\.world"
 *   zregexp_string_free(escaped);
 */
char* zregexp_escape(const char* input);

/**
 * Test if a string is a valid regex pattern.
 *
 * @param pattern Pattern string (null-terminated)
 * @return true if valid, false otherwise
 */
bool zregexp_is_valid_pattern(const char* pattern);

#ifdef __cplusplus
}
#endif

#endif /* ZREGEXP_H */
