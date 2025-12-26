/**
 * C++ Example for zregexp
 *
 * This example demonstrates how to use the C++ wrapper API.
 *
 * Compile:
 *   g++ -std=c++17 cpp_example.cpp -I../include -L../zig-out/lib -lzregexp -o cpp_example
 *
 * Run:
 *   LD_LIBRARY_PATH=../zig-out/lib ./cpp_example
 */

#include <iostream>
#include <zregexp.hpp>

int main() {
    std::cout << "=== zregexp C++ Wrapper Example ===" << std::endl;
    std::cout << "Version: " << zregexp::version() << std::endl << std::endl;

    // Example 1: Basic matching
    std::cout << "Example 1: Basic matching" << std::endl;
    try {
        auto re = zregexp::Regex::compile("hello (\\w+)");
        auto match = re.find("hello world");

        if (match) {
            std::cout << "  Match found: " << match->slice() << std::endl;
            std::cout << "  Position: " << match->start() << "-" << match->end() << std::endl;

            auto group1 = match->group(1);
            if (group1) {
                std::cout << "  Group 1: " << *group1 << std::endl;
            }
        } else {
            std::cout << "  No match found" << std::endl;
        }
    } catch (const zregexp::RegexError& e) {
        std::cerr << "  Error: " << e.what() << std::endl;
    }
    std::cout << std::endl;

    // Example 2: Find all matches
    std::cout << "Example 2: Find all matches" << std::endl;
    try {
        auto re = zregexp::Regex::compile("\\d+");
        auto matches = re.findAll("There are 123 apples and 456 oranges");

        std::cout << "  Found " << matches.size() << " matches:" << std::endl;
        for (const auto& match : matches) {
            std::cout << "    - " << match.slice() << " at position "
                      << match.start() << std::endl;
        }
    } catch (const zregexp::RegexError& e) {
        std::cerr << "  Error: " << e.what() << std::endl;
    }
    std::cout << std::endl;

    // Example 3: Pattern testing
    std::cout << "Example 3: Pattern testing (isMatch)" << std::endl;
    try {
        auto re = zregexp::Regex::compile("^[a-z]+$");

        std::string test1 = "hello";
        std::string test2 = "Hello";
        std::string test3 = "hello123";

        std::cout << "  \"" << test1 << "\" matches: "
                  << (re.isMatch(test1) ? "yes" : "no") << std::endl;
        std::cout << "  \"" << test2 << "\" matches: "
                  << (re.isMatch(test2) ? "yes" : "no") << std::endl;
        std::cout << "  \"" << test3 << "\" matches: "
                  << (re.isMatch(test3) ? "yes" : "no") << std::endl;
    } catch (const zregexp::RegexError& e) {
        std::cerr << "  Error: " << e.what() << std::endl;
    }
    std::cout << std::endl;

    // Example 4: String replacement
    std::cout << "Example 4: String replacement" << std::endl;
    try {
        auto re = zregexp::Regex::compile("\\d+");
        std::string input = "I have 10 apples and 20 oranges";
        std::string result = re.replace(input, "many");

        std::cout << "  Input:  " << input << std::endl;
        std::cout << "  Result: " << result << std::endl;
    } catch (const zregexp::RegexError& e) {
        std::cerr << "  Error: " << e.what() << std::endl;
    }
    std::cout << std::endl;

    // Example 5: Case-insensitive matching
    std::cout << "Example 5: Case-insensitive matching" << std::endl;
    try {
        zregexp::Options opts;
        opts.case_insensitive = true;

        auto re = zregexp::Regex::compile("hello", opts);

        std::cout << "  \"hello\" matches: "
                  << (re.isMatch("hello") ? "yes" : "no") << std::endl;
        std::cout << "  \"HELLO\" matches: "
                  << (re.isMatch("HELLO") ? "yes" : "no") << std::endl;
        std::cout << "  \"HeLLo\" matches: "
                  << (re.isMatch("HeLLo") ? "yes" : "no") << std::endl;
    } catch (const zregexp::RegexError& e) {
        std::cerr << "  Error: " << e.what() << std::endl;
    }
    std::cout << std::endl;

    // Example 6: Escape special characters
    std::cout << "Example 6: Escape special characters" << std::endl;
    std::string special = "hello.world";
    std::string escaped = zregexp::escape(special);
    std::cout << "  Original: " << special << std::endl;
    std::cout << "  Escaped:  " << escaped << std::endl;
    std::cout << std::endl;

    // Example 7: Validate pattern
    std::cout << "Example 7: Validate pattern" << std::endl;
    std::string valid_pattern = "hello.*world";
    std::string invalid_pattern = "hello(world";  // Unmatched paren

    std::cout << "  \"" << valid_pattern << "\" is valid: "
              << (zregexp::isValidPattern(valid_pattern) ? "yes" : "no") << std::endl;
    std::cout << "  \"" << invalid_pattern << "\" is valid: "
              << (zregexp::isValidPattern(invalid_pattern) ? "yes" : "no") << std::endl;
    std::cout << std::endl;

    // Example 8: Capture groups
    std::cout << "Example 8: Capture groups" << std::endl;
    try {
        auto re = zregexp::Regex::compile("(\\w+)@(\\w+)\\.(\\w+)");
        auto match = re.find("user@example.com");

        if (match) {
            std::cout << "  Full match: " << match->slice() << std::endl;

            for (uint8_t i = 1; i <= 3; i++) {
                auto group = match->group(i);
                if (group) {
                    std::cout << "  Group " << static_cast<int>(i) << ": " << *group << std::endl;
                }
            }
        }
    } catch (const zregexp::RegexError& e) {
        std::cerr << "  Error: " << e.what() << std::endl;
    }
    std::cout << std::endl;

    // Example 9: Error handling
    std::cout << "Example 9: Error handling" << std::endl;
    try {
        // This should throw due to unmatched parenthesis
        auto re = zregexp::Regex::compile("hello(world");
        std::cout << "  Pattern compiled successfully (unexpected!)" << std::endl;
    } catch (const zregexp::SyntaxError& e) {
        std::cout << "  Caught SyntaxError: " << e.what() << std::endl;
    } catch (const zregexp::RegexError& e) {
        std::cout << "  Caught RegexError: " << e.what() << std::endl;
    }
    std::cout << std::endl;

    // Example 10: Lookahead and lookbehind
    std::cout << "Example 10: Lookahead assertion" << std::endl;
    try {
        auto re = zregexp::Regex::compile("foo(?=bar)");

        auto match1 = re.find("foobar");
        auto match2 = re.find("foobaz");

        std::cout << "  \"foobar\" matches: " << (match1.has_value() ? "yes" : "no");
        if (match1) {
            std::cout << " (matched: \"" << match1->slice() << "\")";
        }
        std::cout << std::endl;

        std::cout << "  \"foobaz\" matches: " << (match2.has_value() ? "yes" : "no") << std::endl;
    } catch (const zregexp::RegexError& e) {
        std::cerr << "  Error: " << e.what() << std::endl;
    }
    std::cout << std::endl;

    std::cout << "=== All examples completed ===" << std::endl;

    return 0;
}
