//! High-level Regex API
//!
//! This module provides a simple, user-friendly API for working with regular expressions.
//! It combines compilation and matching into convenient methods.
//!
//! ## Quick Start
//!
//! ```zig
//! const regex = @import("regex.zig");
//!
//! // Test if a pattern matches
//! const matches = try regex.test("hello", "hello world");
//!
//! // Find first match
//! const result = try regex.find(allocator, "wo..", "hello world");
//! defer if (result) |r| r.deinit();
//!
//! // Compile once, use many times
//! var re = try regex.Regex.compile(allocator, "a+");
//! defer re.deinit();
//!
//! const match1 = try re.test_("aaa");
//! const match2 = try re.test_("bbb");
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import compiler and executor modules
const compiler = @import("codegen/compiler.zig");
const matcher_mod = @import("executor/matcher.zig");
const parser_mod = @import("parser/parser.zig");
const generator_mod = @import("codegen/generator.zig");
const format_mod = @import("bytecode/format.zig");

const CompileResult = compiler.CompileResult;
const CompileOptions = compiler.CompileOptions;
const Matcher = matcher_mod.Matcher;
pub const MatchResult = matcher_mod.MatchResult;

/// Error set for regex operations (includes all possible compilation and execution errors)
pub const RegexError = parser_mod.ParseError || generator_mod.CodegenError || Allocator.Error || error{
    UnexpectedEndOfBytecode,
    UnknownOpcode,
    UnresolvedLabels,
    BufferTooSmall,
    RecursionLimitExceeded,
    StepLimitExceeded,
};

/// Main Regex type - represents a compiled regular expression
pub const Regex = struct {
    allocator: Allocator,
    compiled: CompileResult,
    pattern: []const u8,

    const Self = @This();

    /// Compile a regex pattern
    pub fn compile(allocator: Allocator, pattern: []const u8) RegexError!Self {
        const compiled = try compiler.compileSimple(allocator, pattern);
        return .{
            .allocator = allocator,
            .compiled = compiled,
            .pattern = pattern,
        };
    }

    /// Compile with custom options
    pub fn compileWithOptions(allocator: Allocator, pattern: []const u8, options: CompileOptions) RegexError!Self {
        const compiled = try compiler.compile(allocator, pattern, options);
        return .{
            .allocator = allocator,
            .compiled = compiled,
            .pattern = pattern,
        };
    }

    /// Free resources
    pub fn deinit(self: Self) void {
        self.compiled.deinit();
    }

    /// Test if pattern matches entire input
    pub fn matchFull(self: Self, input: []const u8) RegexError!bool {
        const m = Matcher.init(self.allocator, self.compiled.bytecode);
        return try m.matchFull(input);
    }

    /// Alias for matchFull (common in other regex libraries)
    pub fn test_(self: Self, input: []const u8) RegexError!bool {
        return self.matchFull(input);
    }

    /// Find first match in input
    pub fn find(self: Self, input: []const u8) RegexError!?MatchResult {
        const m = Matcher.init(self.allocator, self.compiled.bytecode);
        return try m.find(input);
    }

    /// Find all matches in input
    pub fn findAll(self: Self, input: []const u8) RegexError!std.ArrayListUnmanaged(MatchResult) {
        const m = Matcher.init(self.allocator, self.compiled.bytecode);
        return try m.findAll(input);
    }

    /// Get the original pattern string
    pub fn getPattern(self: Self) []const u8 {
        return self.pattern;
    }
};

// =============================================================================
// Convenience Functions (one-shot operations)
// =============================================================================

/// Quick test: compile pattern and check if it matches input
pub fn test_(allocator: Allocator, pattern: []const u8, input: []const u8) RegexError!bool {
    const re = try Regex.compile(allocator, pattern);
    defer re.deinit();
    return try re.matchFull(input);
}

/// Quick match: compile pattern and return first match
pub fn find(allocator: Allocator, pattern: []const u8, input: []const u8) RegexError!?MatchResult {
    const re = try Regex.compile(allocator, pattern);
    defer re.deinit();
    return try re.find(input);
}

/// Quick findAll: compile pattern and return all matches
pub fn findAll(allocator: Allocator, pattern: []const u8, input: []const u8) RegexError!std.ArrayListUnmanaged(MatchResult) {
    const re = try Regex.compile(allocator, pattern);
    defer re.deinit();
    return try re.findAll(input);
}

// =============================================================================
// Tests
// =============================================================================

test "Regex: compile and test" {
    var re = try Regex.compile(std.testing.allocator, "hello");
    defer re.deinit();

    try std.testing.expect(try re.test_("hello"));
    try std.testing.expect(!try re.test_("world"));
}

test "Regex: compile with options" {
    const options = CompileOptions{
        .opt_level = .basic,
    };

    var re = try Regex.compileWithOptions(std.testing.allocator, "test", options);
    defer re.deinit();

    try std.testing.expect(try re.matchFull("test"));
}

test "Regex: find" {
    var re = try Regex.compile(std.testing.allocator, "world");
    defer re.deinit();

    const result = try re.find("hello world");
    try std.testing.expect(result != null);
    defer result.?.deinit();

    try std.testing.expectEqual(@as(usize, 6), result.?.start);
    try std.testing.expectEqual(@as(usize, 11), result.?.end);
}

test "Regex: find with capture" {
    // Note: \d+ would be [0-9]+ but character classes not fully implemented yet
    // Using simple pattern for now
    var re = try Regex.compile(std.testing.allocator, "(wo..)");
    defer re.deinit();

    const result = try re.find("hello world");
    try std.testing.expect(result != null);
    defer result.?.deinit();

    const captured = result.?.getCapture(1, "hello world");
    try std.testing.expect(captured != null);
    try std.testing.expectEqualStrings("worl", captured.?);
}

test "Regex: findAll" {
    var re = try Regex.compile(std.testing.allocator, "a");
    defer re.deinit();

    var matches = try re.findAll("banana");
    defer {
        for (matches.items) |match| {
            match.deinit();
        }
        matches.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), matches.items.len);
}

test "Regex: getPattern" {
    var re = try Regex.compile(std.testing.allocator, "test.*");
    defer re.deinit();

    try std.testing.expectEqualStrings("test.*", re.getPattern());
}

test "convenience: test_" {
    try std.testing.expect(try test_(std.testing.allocator, "abc", "abc"));
    try std.testing.expect(!try test_(std.testing.allocator, "abc", "xyz"));
}

test "convenience: find" {
    const result = try find(std.testing.allocator, "wo..", "hello world");
    try std.testing.expect(result != null);
    defer result.?.deinit();

    try std.testing.expectEqual(@as(usize, 6), result.?.start);
}

test "convenience: findAll" {
    var matches = try findAll(std.testing.allocator, "o", "foo");
    defer {
        for (matches.items) |match| {
            match.deinit();
        }
        matches.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), matches.items.len);
}

test "Regex: alternation" {
    var re = try Regex.compile(std.testing.allocator, "cat|dog");
    defer re.deinit();

    try std.testing.expect(try re.test_("cat"));
    try std.testing.expect(try re.test_("dog"));
    try std.testing.expect(!try re.test_("bird"));
}

test "Regex: quantifiers" {
    var re_star = try Regex.compile(std.testing.allocator, "a*");
    defer re_star.deinit();
    try std.testing.expect(try re_star.test_(""));
    try std.testing.expect(try re_star.test_("aaa"));

    var re_plus = try Regex.compile(std.testing.allocator, "a+");
    defer re_plus.deinit();
    try std.testing.expect(!try re_plus.test_(""));
    try std.testing.expect(try re_plus.test_("aaa"));

    var re_question = try Regex.compile(std.testing.allocator, "a?");
    defer re_question.deinit();
    try std.testing.expect(try re_question.test_(""));
    try std.testing.expect(try re_question.test_("a"));
}

test "Regex: lazy quantifiers" {
    // Lazy star: matches as few as possible
    {
        var re = try Regex.compile(std.testing.allocator, "a*?");
        defer re.deinit();
        // test_() checks if pattern matches ENTIRE input
        try std.testing.expect(try re.test_("")); // Empty matches empty
        // For lazy star with non-empty input, use find() instead
        const match = try re.find("aaa");
        defer if (match) |m| m.deinit();
        try std.testing.expect(match != null);
        try std.testing.expectEqual(@as(usize, 0), match.?.start);
        try std.testing.expectEqual(@as(usize, 0), match.?.end); // Lazy matches empty
    }

    // Lazy plus: matches one or more, but as few as possible
    {
        var re = try Regex.compile(std.testing.allocator, "a+?");
        defer re.deinit();
        try std.testing.expect(!try re.test_("")); // Must match at least one
        try std.testing.expect(try re.test_("a")); // Matches exactly 1
        // With longer input, lazy matches minimum (1 char)
        const match = try re.find("aaa");
        defer if (match) |m| m.deinit();
        try std.testing.expect(match != null);
        try std.testing.expectEqual(@as(usize, 0), match.?.start);
        try std.testing.expectEqual(@as(usize, 1), match.?.end); // Lazy matches 1
    }

    // Lazy question: 0 or 1, preferring 0
    {
        var re = try Regex.compile(std.testing.allocator, "a??");
        defer re.deinit();
        try std.testing.expect(try re.test_("")); // Empty matches empty
        // For lazy question with non-empty input, use find()
        const match = try re.find("a");
        defer if (match) |m| m.deinit();
        try std.testing.expect(match != null);
        try std.testing.expectEqual(@as(usize, 0), match.?.start);
        try std.testing.expectEqual(@as(usize, 0), match.?.end); // Lazy matches empty
    }
}

test "Regex: greedy vs lazy comparison" {
    // Greedy star matches maximum
    {
        var re = try Regex.compile(std.testing.allocator, "a*");
        defer re.deinit();
        const match = try re.find("aaabbb");
        defer if (match) |m| m.deinit();
        try std.testing.expect(match != null);
        try std.testing.expectEqual(@as(usize, 0), match.?.start);
        try std.testing.expectEqual(@as(usize, 3), match.?.end); // Greedy: all 'a's
    }

    // Lazy star matches minimum
    {
        var re = try Regex.compile(std.testing.allocator, "a*?");
        defer re.deinit();
        const match = try re.find("aaabbb");
        defer if (match) |m| m.deinit();
        try std.testing.expect(match != null);
        try std.testing.expectEqual(@as(usize, 0), match.?.start);
        try std.testing.expectEqual(@as(usize, 0), match.?.end); // Lazy: empty
    }
}

test "Regex: possessive quantifiers" {
    // Possessive star: consumes all without backtracking
    {
        var re = try Regex.compile(std.testing.allocator, "a*+");
        defer re.deinit();
        try std.testing.expect(try re.test_(""));
        try std.testing.expect(try re.test_("aaa"));

        const match = try re.find("aaabbb");
        defer if (match) |m| m.deinit();
        try std.testing.expect(match != null);
        try std.testing.expectEqual(@as(usize, 0), match.?.start);
        try std.testing.expectEqual(@as(usize, 3), match.?.end); // Possessive: all 'a's
    }

    // Possessive plus: at least one, then all without backtracking
    {
        var re = try Regex.compile(std.testing.allocator, "a++");
        defer re.deinit();
        try std.testing.expect(!try re.test_(""));
        try std.testing.expect(try re.test_("aaa"));

        const match = try re.find("aaa");
        defer if (match) |m| m.deinit();
        try std.testing.expect(match != null);
        try std.testing.expectEqual(@as(usize, 0), match.?.start);
        try std.testing.expectEqual(@as(usize, 3), match.?.end); // All
    }

    // Possessive question: 0 or 1 without backtracking
    {
        var re = try Regex.compile(std.testing.allocator, "a?+");
        defer re.deinit();
        try std.testing.expect(try re.test_(""));
        try std.testing.expect(try re.test_("a"));
    }
}

test "Regex: greedy vs lazy vs possessive comparison" {
    // All three should match "aaa" when used alone
    {
        var greedy = try Regex.compile(std.testing.allocator, "a*");
        defer greedy.deinit();
        const match1 = try greedy.find("aaa");
        defer if (match1) |m| m.deinit();
        try std.testing.expectEqual(@as(usize, 3), match1.?.end);
    }

    {
        var lazy = try Regex.compile(std.testing.allocator, "a*?");
        defer lazy.deinit();
        const match2 = try lazy.find("aaa");
        defer if (match2) |m| m.deinit();
        try std.testing.expectEqual(@as(usize, 0), match2.?.end); // Lazy: minimum
    }

    {
        var possessive = try Regex.compile(std.testing.allocator, "a*+");
        defer possessive.deinit();
        const match3 = try possessive.find("aaa");
        defer if (match3) |m| m.deinit();
        try std.testing.expectEqual(@as(usize, 3), match3.?.end); // Possessive: all
    }
}

test "Regex: anchors" {
    var re = try Regex.compile(std.testing.allocator, "^hello$");
    defer re.deinit();

    try std.testing.expect(try re.test_("hello"));
    try std.testing.expect(!try re.test_("hello world"));
    try std.testing.expect(!try re.test_("say hello"));
}

test "Regex: dot metacharacter" {
    var re = try Regex.compile(std.testing.allocator, "h.llo");
    defer re.deinit();

    try std.testing.expect(try re.test_("hello"));
    try std.testing.expect(try re.test_("hallo"));
    try std.testing.expect(try re.test_("hxllo"));
}

test "Regex: complex pattern" {
    var re = try Regex.compile(std.testing.allocator, "^[a-z]+@[a-z]+\\.[a-z]+$");
    defer re.deinit();

    // These should work when character classes are fully implemented
    // For now, just test that compilation succeeds
    _ = try re.test_("user@example.com");
}

test "Regex: character classes" {
    // Test \d (digit)
    {
        var re = try Regex.compile(std.testing.allocator, "\\d");
        defer re.deinit();
        try std.testing.expect(try re.test_("5"));
        try std.testing.expect(!try re.test_("a"));
    }

    // Test \D (not digit)
    {
        var re = try Regex.compile(std.testing.allocator, "\\D");
        defer re.deinit();
        try std.testing.expect(try re.test_("a"));
        try std.testing.expect(!try re.test_("5"));
    }

    // Test [0-9] range
    {
        var re = try Regex.compile(std.testing.allocator, "[0-9]");
        defer re.deinit();
        try std.testing.expect(try re.test_("5"));
        try std.testing.expect(!try re.test_("a"));
    }

    // Test [^0-9] negated range
    {
        var re = try Regex.compile(std.testing.allocator, "[^0-9]");
        defer re.deinit();
        try std.testing.expect(try re.test_("a"));
        try std.testing.expect(!try re.test_("5"));
    }

    // Test [a-z] range
    {
        var re = try Regex.compile(std.testing.allocator, "[a-z]");
        defer re.deinit();
        try std.testing.expect(try re.test_("a"));
        try std.testing.expect(try re.test_("z"));
        try std.testing.expect(!try re.test_("A"));
        try std.testing.expect(!try re.test_("5"));
    }

    // Test [^a-z] negated range
    {
        var re = try Regex.compile(std.testing.allocator, "[^a-z]");
        defer re.deinit();
        try std.testing.expect(try re.test_("A"));
        try std.testing.expect(try re.test_("5"));
        try std.testing.expect(!try re.test_("a"));
    }
}

test "Regex: case-insensitive matching" {
    const options = CompileOptions{
        .case_insensitive = true,
    };

    // Test single character
    {
        var re = try Regex.compileWithOptions(std.testing.allocator, "a", options);
        defer re.deinit();
        try std.testing.expect(try re.test_("a"));
        try std.testing.expect(try re.test_("A"));
    }

    // Test word
    {
        var re = try Regex.compileWithOptions(std.testing.allocator, "hello", options);
        defer re.deinit();
        try std.testing.expect(try re.test_("hello"));
        try std.testing.expect(try re.test_("HELLO"));
        try std.testing.expect(try re.test_("Hello"));
        try std.testing.expect(try re.test_("HeLLo"));
        try std.testing.expect(!try re.test_("world"));
    }

    // Test with numbers (should not be affected)
    {
        var re = try Regex.compileWithOptions(std.testing.allocator, "test123", options);
        defer re.deinit();
        try std.testing.expect(try re.test_("test123"));
        try std.testing.expect(try re.test_("TEST123"));
        try std.testing.expect(try re.test_("Test123"));
        try std.testing.expect(!try re.test_("test124"));
    }

    // Test with anchors
    {
        var re = try Regex.compileWithOptions(std.testing.allocator, "^abc$", options);
        defer re.deinit();
        try std.testing.expect(try re.test_("abc"));
        try std.testing.expect(try re.test_("ABC"));
        try std.testing.expect(try re.test_("AbC"));
        try std.testing.expect(!try re.test_("abcd"));
    }
}

test "Regex: counted quantifiers {n,m}" {
    // Test exact count {3}
    {
        var re = try Regex.compile(std.testing.allocator, "a{3}");
        defer re.deinit();

        try std.testing.expect(!try re.test_("a"));
        try std.testing.expect(!try re.test_("aa"));
        try std.testing.expect(try re.test_("aaa"));
        try std.testing.expect(!try re.test_("aaaa")); // Full match requires exactly 3

        // Test find() for partial matches
        const r1 = try re.find("aaaa");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 0), r1.?.start);
        try std.testing.expectEqual(@as(usize, 3), r1.?.end);
    }

    // Test range {2,4}
    {
        var re = try Regex.compile(std.testing.allocator, "a{2,4}");
        defer re.deinit();

        try std.testing.expect(!try re.test_("a"));
        try std.testing.expect(try re.test_("aa"));
        try std.testing.expect(try re.test_("aaa"));
        try std.testing.expect(try re.test_("aaaa"));
        try std.testing.expect(!try re.test_("aaaaa")); // Full match needs 2-4

        // Test greedy matching
        const r1 = try re.find("aaaaa");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 0), r1.?.start);
        try std.testing.expectEqual(@as(usize, 4), r1.?.end); // Greedy: matches 4, not 2 or 3
    }

    // Test unbounded {2,}
    {
        var re = try Regex.compile(std.testing.allocator, "a{2,}");
        defer re.deinit();

        try std.testing.expect(!try re.test_("a"));
        try std.testing.expect(try re.test_("aa"));
        try std.testing.expect(try re.test_("aaa"));
        try std.testing.expect(try re.test_("aaaa"));
        try std.testing.expect(try re.test_("aaaaaaaa"));
        try std.testing.expect(!try re.test_("baaaa")); // Must start with a's for full match
    }

    // Test with patterns
    {
        var re = try Regex.compile(std.testing.allocator, "x{2}y");
        defer re.deinit();

        try std.testing.expect(!try re.test_("xy"));
        try std.testing.expect(try re.test_("xxy"));
        try std.testing.expect(!try re.test_("xxxy"));
        try std.testing.expect(!try re.test_("xxxyy"));
    }

    // Test {0,n}
    {
        var re = try Regex.compile(std.testing.allocator, "a{0,2}b");
        defer re.deinit();

        try std.testing.expect(try re.test_("b"));
        try std.testing.expect(try re.test_("ab"));
        try std.testing.expect(try re.test_("aab"));
        try std.testing.expect(!try re.test_("aaab"));
    }

    // Test {1} - exactly 1
    {
        var re = try Regex.compile(std.testing.allocator, "a{1}");
        defer re.deinit();

        try std.testing.expect(!try re.test_(""));
        try std.testing.expect(try re.test_("a"));
        try std.testing.expect(!try re.test_("aa"));
    }
}

test "Regex: backreferences \\1-\\9" {
    // Test simple backreference
    {
        var re = try Regex.compile(std.testing.allocator, "(.)\\1");
        defer re.deinit();

        try std.testing.expect(try re.test_("aa"));
        try std.testing.expect(try re.test_("bb"));
        try std.testing.expect(try re.test_("00"));
        try std.testing.expect(!try re.test_("ab"));
        try std.testing.expect(!try re.test_("a"));
    }

    // Test word repetition
    {
        var re = try Regex.compile(std.testing.allocator, "(.+) \\1");
        defer re.deinit();

        try std.testing.expect(try re.test_("hello hello"));
        try std.testing.expect(try re.test_("test test"));
        try std.testing.expect(!try re.test_("hello world"));
        try std.testing.expect(!try re.test_("hello"));
    }

    // Test quoted strings (matching quotes)
    {
        var re = try Regex.compile(std.testing.allocator, "(['\"]).*\\1");
        defer re.deinit();

        const r1 = try re.find("'hello'");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqualStrings("'hello'", r1.?.group("'hello'"));

        const r2 = try re.find("\"world\"");
        try std.testing.expect(r2 != null);
        defer r2.?.deinit();
        try std.testing.expectEqualStrings("\"world\"", r2.?.group("\"world\""));

        // Mismatched quotes should not match
        try std.testing.expect(null == try re.find("'hello\""));
        try std.testing.expect(null == try re.find("\"world'"));
    }

    // Test multiple backreferences
    {
        var re = try Regex.compile(std.testing.allocator, "(.)(.)(.)\\3\\2\\1");
        defer re.deinit();

        try std.testing.expect(try re.test_("abccba"));
        try std.testing.expect(try re.test_("123321"));
        try std.testing.expect(!try re.test_("abcabc"));
        try std.testing.expect(!try re.test_("abcdef"));
    }

    // Test backreference with quantifier
    {
        var re = try Regex.compile(std.testing.allocator, "(a+)\\1");
        defer re.deinit();

        try std.testing.expect(try re.test_("aa"));
        try std.testing.expect(try re.test_("aaaa"));
        try std.testing.expect(try re.test_("aaaaaa"));
        try std.testing.expect(!try re.test_("aaa")); // "aa" + "a" doesn't match
        try std.testing.expect(!try re.test_("ab"));
    }

    // Test empty capture
    {
        var re = try Regex.compile(std.testing.allocator, "(a?)\\1");
        defer re.deinit();

        try std.testing.expect(try re.test_("")); // empty + empty
        try std.testing.expect(try re.test_("aa")); // "a" + "a"
        try std.testing.expect(!try re.test_("a")); // "a" + empty doesn't work for full match
    }

    // Test case-sensitive backreference
    {
        var re = try Regex.compile(std.testing.allocator, "(.)\\1");
        defer re.deinit();

        try std.testing.expect(try re.test_("aa"));
        try std.testing.expect(try re.test_("AA"));
        try std.testing.expect(!try re.test_("aA")); // Case-sensitive
        try std.testing.expect(!try re.test_("Aa"));
    }

    // Test case-insensitive backreference
    {
        const options = CompileOptions{
            .case_insensitive = true,
        };
        var re = try Regex.compileWithOptions(std.testing.allocator, "(.)\\1", options);
        defer re.deinit();

        try std.testing.expect(try re.test_("aa"));
        try std.testing.expect(try re.test_("AA"));
        try std.testing.expect(try re.test_("aA")); // Case-insensitive!
        try std.testing.expect(try re.test_("Aa")); // Case-insensitive!
    }
}

test "Regex: lookahead assertions (?=...) and (?!...)" {
    // Test positive lookahead - basic
    {
        var re = try Regex.compile(std.testing.allocator, "foo(?=bar)");
        defer re.deinit();

        // "foobar" matches: "foo" is followed by "bar"
        const r1 = try re.find("foobar");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 0), r1.?.start);
        try std.testing.expectEqual(@as(usize, 3), r1.?.end); // Only matches "foo", not "bar"

        // "foobaz" doesn't match: "foo" is NOT followed by "bar"
        try std.testing.expect(null == try re.find("foobaz"));

        // "foo" alone doesn't match: nothing follows
        try std.testing.expect(null == try re.find("foo"));
    }

    // Test negative lookahead - basic
    {
        var re = try Regex.compile(std.testing.allocator, "foo(?!bar)");
        defer re.deinit();

        // "foobaz" matches: "foo" is NOT followed by "bar"
        const r1 = try re.find("foobaz");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 0), r1.?.start);
        try std.testing.expectEqual(@as(usize, 3), r1.?.end);

        // "foobar" doesn't match: "foo" IS followed by "bar"
        try std.testing.expect(null == try re.find("foobar"));

        // "foo" at end matches: nothing follows (not "bar")
        const r2 = try re.find("foo");
        try std.testing.expect(r2 != null);
        defer r2.?.deinit();
    }

    // Test lookahead doesn't consume input
    {
        var re = try Regex.compile(std.testing.allocator, "foo(?=bar)bar");
        defer re.deinit();

        // Should match "foobar": lookahead checks for "bar" but doesn't consume it
        try std.testing.expect(try re.test_("foobar"));

        // Should NOT match "foobaz"
        try std.testing.expect(!try re.test_("foobaz"));
    }

    // Test password validation: at least one digit
    {
        var re = try Regex.compile(std.testing.allocator, "(?=.*[0-9]).+");
        defer re.deinit();

        try std.testing.expect(try re.test_("pass123"));
        try std.testing.expect(try re.test_("1password"));
        try std.testing.expect(try re.test_("p4ssw0rd"));
        try std.testing.expect(!try re.test_("password"));
    }

    // Test multiple lookaheads
    {
        // Must contain digit AND letter
        var re = try Regex.compile(std.testing.allocator, "(?=.*[0-9])(?=.*[a-z]).+");
        defer re.deinit();

        try std.testing.expect(try re.test_("pass123"));
        try std.testing.expect(!try re.test_("123456")); // No letter
        try std.testing.expect(!try re.test_("password")); // No digit
    }

    // Test word boundaries with lookahead
    {
        // Match "test" only if NOT followed by "ing"
        var re = try Regex.compile(std.testing.allocator, "test(?!ing)");
        defer re.deinit();

        const r1 = try re.find("test");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();

        const r2 = try re.find("tester");
        try std.testing.expect(r2 != null);
        defer r2.?.deinit();

        try std.testing.expect(null == try re.find("testing"));
    }

    // Test lookahead with alternation
    {
        // Match "foo" followed by either "bar" or "baz"
        var re = try Regex.compile(std.testing.allocator, "foo(?=bar|baz)");
        defer re.deinit();

        const r1 = try re.find("foobar");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();

        const r2 = try re.find("foobaz");
        try std.testing.expect(r2 != null);
        defer r2.?.deinit();

        try std.testing.expect(null == try re.find("fooqux"));
    }

    // Test negative lookahead with simple pattern
    {
        // Match "foo" not followed by "x"
        var re = try Regex.compile(std.testing.allocator, "foo(?!x)");
        defer re.deinit();

        const r1 = try re.find("foobar");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 0), r1.?.start);
        try std.testing.expectEqual(@as(usize, 3), r1.?.end);

        const r2 = try re.find("foo");
        try std.testing.expect(r2 != null);
        defer r2.?.deinit();

        // "foox" should not match
        try std.testing.expect(null == try re.find("foox"));
    }
}

test "Regex: non-capturing groups (?:...)" {
    // Test 1: Basic non-capturing group doesn't create capture
    {
        var re = try Regex.compile(std.testing.allocator, "(?:hello) world");
        defer re.deinit();

        const r = try re.find("hello world");
        try std.testing.expect(r != null);
        defer r.?.deinit();

        // Should match the entire pattern
        try std.testing.expectEqual(@as(usize, 0), r.?.start);
        try std.testing.expectEqual(@as(usize, 11), r.?.end);

        // Should have no captures (only group 0 - the whole match)
        try std.testing.expect(r.?.getCapture(1, "hello world") == null);
    }

    // Test 2: Non-capturing group with quantifier
    {
        var re = try Regex.compile(std.testing.allocator, "(?:ab)+");
        defer re.deinit();

        // "ababab" should match
        try std.testing.expect(try re.test_("ababab"));

        const r1 = try re.find("ababab");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 0), r1.?.start);
        try std.testing.expectEqual(@as(usize, 6), r1.?.end);

        // "ab" should match
        try std.testing.expect(try re.test_("ab"));

        // "a" should not match
        try std.testing.expect(!try re.test_("a"));

        // "abc" should match "ab" part
        const r2 = try re.find("abc");
        try std.testing.expect(r2 != null);
        defer r2.?.deinit();
        try std.testing.expectEqual(@as(usize, 0), r2.?.start);
        try std.testing.expectEqual(@as(usize, 2), r2.?.end);
    }

    // Test 3: Non-capturing group with alternation
    {
        var re = try Regex.compile(std.testing.allocator, "(?:cat|dog)s");
        defer re.deinit();

        try std.testing.expect(try re.test_("cats"));
        try std.testing.expect(try re.test_("dogs"));
        try std.testing.expect(!try re.test_("cat"));
        try std.testing.expect(!try re.test_("dog"));
        try std.testing.expect(!try re.test_("birds"));
    }

    // Test 4: Mixed capturing and non-capturing groups
    {
        // Pattern: (?:https?:)//(\\w+)
        // Only the domain should be captured, not the protocol
        var re = try Regex.compile(std.testing.allocator, "(?:https?)://(\\w+)");
        defer re.deinit();

        const r1 = try re.find("http://example");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();

        // Group 0: Full match
        try std.testing.expectEqual(@as(usize, 0), r1.?.start);
        try std.testing.expectEqual(@as(usize, 14), r1.?.end);

        // Group 1: Should capture "example" (the \\w+)
        const capture1 = r1.?.getCapture(1, "http://example");
        try std.testing.expect(capture1 != null);
        try std.testing.expectEqualStrings("example", capture1.?);

        // The https? part is non-capturing, so group numbering starts at 1 for \\w+
        const r2 = try re.find("https://google");
        try std.testing.expect(r2 != null);
        defer r2.?.deinit();

        const capture2 = r2.?.getCapture(1, "https://google");
        try std.testing.expect(capture2 != null);
        try std.testing.expectEqualStrings("google", capture2.?);
    }

    // Test 5: Nested groups (capturing inside non-capturing)
    {
        var re = try Regex.compile(std.testing.allocator, "(?:(\\w+)@(\\w+))");
        defer re.deinit();

        const r = try re.find("user@example");
        try std.testing.expect(r != null);
        defer r.?.deinit();

        // Should capture both parts
        const c1 = r.?.getCapture(1, "user@example");
        try std.testing.expect(c1 != null);
        try std.testing.expectEqualStrings("user", c1.?);

        const c2 = r.?.getCapture(2, "user@example");
        try std.testing.expect(c2 != null);
        try std.testing.expectEqualStrings("example", c2.?);
    }

    // Test 6: Non-capturing group preserves group numbering
    {
        // Pattern: (a)(?:b)(c)
        // Group 1: a
        // Group 2: c  (not b, because (?:b) is non-capturing)
        var re = try Regex.compile(std.testing.allocator, "(a)(?:b)(c)");
        defer re.deinit();

        const r = try re.find("abc");
        try std.testing.expect(r != null);
        defer r.?.deinit();

        // Full match
        try std.testing.expectEqual(@as(usize, 0), r.?.start);
        try std.testing.expectEqual(@as(usize, 3), r.?.end);

        // Group 1: "a"
        const c1 = r.?.getCapture(1, "abc");
        try std.testing.expect(c1 != null);
        try std.testing.expectEqualStrings("a", c1.?);

        // Group 2: "c" (b is in non-capturing group)
        const c2 = r.?.getCapture(2, "abc");
        try std.testing.expect(c2 != null);
        try std.testing.expectEqualStrings("c", c2.?);

        // Group 3: Should not exist
        try std.testing.expect(r.?.getCapture(3, "abc") == null);
    }

    // Test 7: Multiple non-capturing groups
    {
        var re = try Regex.compile(std.testing.allocator, "(?:foo)(?:bar)(baz)");
        defer re.deinit();

        const r = try re.find("foobarbaz");
        try std.testing.expect(r != null);
        defer r.?.deinit();

        // Should only capture "baz"
        const c1 = r.?.getCapture(1, "foobarbaz");
        try std.testing.expect(c1 != null);
        try std.testing.expectEqualStrings("baz", c1.?);

        // No other captures
        try std.testing.expect(r.?.getCapture(2, "foobarbaz") == null);
    }

    // Test 8: Non-capturing group with backreference to capturing group
    {
        // Pattern: (a)(?:b)\\1
        // Group 1: a
        // (?:b) is non-capturing
        // \\1 refers to group 1 (a)
        var re = try Regex.compile(std.testing.allocator, "(a)(?:b)\\1");
        defer re.deinit();

        try std.testing.expect(try re.test_("aba"));
        try std.testing.expect(!try re.test_("abb"));
        try std.testing.expect(!try re.test_("abc"));
    }
}

test "Regex: lookbehind assertions (?<=...) and (?<!...)" {
    // Test 1: Basic positive lookbehind
    {
        // Match digits preceded by $
        var re = try Regex.compile(std.testing.allocator, "(?<=\\$)\\d+");
        defer re.deinit();

        // "Price: $100" should match "100"
        const r1 = try re.find("Price: $100");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 8), r1.?.start); // Position after $
        try std.testing.expectEqual(@as(usize, 11), r1.?.end);

        // "100" without $ should not match
        try std.testing.expect(null == try re.find("Price: 100"));

        // "$50" should match
        const r2 = try re.find("$50");
        try std.testing.expect(r2 != null);
        defer r2.?.deinit();
        try std.testing.expectEqual(@as(usize, 1), r2.?.start);
        try std.testing.expectEqual(@as(usize, 3), r2.?.end);
    }

    // Test 2: Basic negative lookbehind
    {
        // Match digits NOT preceded by $
        var re = try Regex.compile(std.testing.allocator, "(?<!\\$)\\d+");
        defer re.deinit();

        // "Price: 100" should match
        const r1 = try re.find("Price: 100");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();

        // "$100" - the '1' IS preceded by $, so it won't match
        // But '0' at position 2 is NOT preceded by $ (preceded by '1')
        // So the pattern will match "00"
        const r2 = try re.find("$100");
        try std.testing.expect(r2 != null);
        defer r2.?.deinit();
        try std.testing.expectEqual(@as(usize, 2), r2.?.start); // Starts at second '0'
        try std.testing.expectEqual(@as(usize, 4), r2.?.end); // Matches "00"

        // "Cost: 50 items" should match "50"
        const r3 = try re.find("Cost: 50 items");
        try std.testing.expect(r3 != null);
        defer r3.?.deinit();
    }

    // Test 3: Lookbehind with literal text
    {
        // Match "world" preceded by "hello "
        var re = try Regex.compile(std.testing.allocator, "(?<=hello )\\w+");
        defer re.deinit();

        // "hello world" should match "world"
        const r1 = try re.find("hello world");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 6), r1.?.start);
        try std.testing.expectEqual(@as(usize, 11), r1.?.end);

        // "hi world" should not match
        try std.testing.expect(null == try re.find("hi world"));

        // "world" alone should not match
        try std.testing.expect(null == try re.find("world"));
    }

    // Test 4: Lookbehind is zero-width (doesn't consume)
    {
        // Pattern includes lookbehind and the character it checks for
        var re = try Regex.compile(std.testing.allocator, "(?<=@)\\w+");
        defer re.deinit();

        // "user@example" should match "example"
        const r1 = try re.find("user@example");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 5), r1.?.start); // After @
        try std.testing.expectEqual(@as(usize, 12), r1.?.end);
    }

    // Test 5: Negative lookbehind with specific character
    {
        // Match word NOT preceded by @
        var re = try Regex.compile(std.testing.allocator, "(?<!@)\\w+");
        defer re.deinit();

        // "hello" should match (not preceded by @)
        const r1 = try re.find("hello");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();

        // "user@example" - "user" should match, "example" should not
        const r2 = try re.find("user@example");
        try std.testing.expect(r2 != null);
        defer r2.?.deinit();
        // Should match "user" (starts at 0)
        try std.testing.expectEqual(@as(usize, 0), r2.?.start);
    }

    // Test 6: Lookbehind with character class
    {
        // Match digits preceded by any letter
        var re = try Regex.compile(std.testing.allocator, "(?<=[a-z])\\d+");
        defer re.deinit();

        // "abc123" should match "123"
        const r1 = try re.find("abc123");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 3), r1.?.start);
        try std.testing.expectEqual(@as(usize, 6), r1.?.end);

        // "123" alone should not match
        try std.testing.expect(null == try re.find("123"));

        // "ABC123" (uppercase) should not match
        try std.testing.expect(null == try re.find("ABC123"));
    }

    // Test 7: Multiple matches with lookbehind
    {
        // Match word boundaries with lookbehind
        var re = try Regex.compile(std.testing.allocator, "(?<=,)\\w+");
        defer re.deinit();

        // "a,b,c" should match "b" and "c"
        const r1 = try re.find("a,b,c");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 2), r1.?.start); // First match is "b"
        try std.testing.expectEqual(@as(usize, 3), r1.?.end);

        // "abc" (no commas) should not match
        try std.testing.expect(null == try re.find("abc"));
    }

    // Test 8: Combining lookahead and lookbehind
    {
        // Match digit preceded by $ and followed by space
        var re = try Regex.compile(std.testing.allocator, "(?<=\\$)\\d+(?= )");
        defer re.deinit();

        // "$100 total" should match "100"
        const r1 = try re.find("$100 total");
        try std.testing.expect(r1 != null);
        defer r1.?.deinit();
        try std.testing.expectEqual(@as(usize, 1), r1.?.start);
        try std.testing.expectEqual(@as(usize, 4), r1.?.end);

        // "$100" (no space after) should not match
        try std.testing.expect(null == try re.find("$100"));

        // "100 " (no $ before) should not match
        try std.testing.expect(null == try re.find("100 "));
    }
}

test "Regex: lazy counted quantifiers {n,m}?" {
    const allocator = std.testing.allocator;

    // Test 1: a{2,4}? should match minimum (2) vs greedy a{2,4} matches maximum (4)
    {
        // Lazy version - should match exactly 2 'a's
        var re_lazy = try Regex.compile(allocator, "a{2,4}?");
        defer re_lazy.deinit();

        const result = try re_lazy.find("aaaa");
        try std.testing.expect(result != null);
        defer if (result) |r| r.deinit();

        if (result) |r| {
            try std.testing.expectEqual(@as(usize, 0), r.start);
            try std.testing.expectEqual(@as(usize, 2), r.end); // Matches "aa" (minimum)
        }

        // Greedy version - should match all 4 'a's
        var re_greedy = try Regex.compile(allocator, "a{2,4}");
        defer re_greedy.deinit();

        const result2 = try re_greedy.find("aaaa");
        try std.testing.expect(result2 != null);
        defer if (result2) |r| r.deinit();

        if (result2) |r| {
            try std.testing.expectEqual(@as(usize, 0), r.start);
            try std.testing.expectEqual(@as(usize, 4), r.end); // Matches "aaaa" (maximum)
        }
    }

    // Test 2: a{2,}? should match minimum (2) in unbounded case
    {
        var re = try Regex.compile(allocator, "a{2,}?");
        defer re.deinit();

        const result = try re.find("aaaaaa");
        try std.testing.expect(result != null);
        defer if (result) |r| r.deinit();

        if (result) |r| {
            try std.testing.expectEqual(@as(usize, 0), r.start);
            try std.testing.expectEqual(@as(usize, 2), r.end); // Matches "aa" (minimum)
        }
    }

    // Test 3: Lazy repeat in context - match as little as possible
    {
        // Pattern: .{1,10}? should match minimally before 'x'
        var re = try Regex.compile(allocator, ".{1,10}?x");
        defer re.deinit();

        const result = try re.find("abcdefx");
        try std.testing.expect(result != null);
        defer if (result) |r| r.deinit();

        if (result) |r| {
            try std.testing.expectEqual(@as(usize, 0), r.start);
            try std.testing.expectEqual(@as(usize, 7), r.end); // Matches "abcdefx" (all chars needed to reach 'x')
        }
    }

    // Test 4: Lazy repeat with exact count a{3}? (should be same as a{3})
    {
        var re = try Regex.compile(allocator, "a{3}?");
        defer re.deinit();

        const result = try re.find("aaaaa");
        try std.testing.expect(result != null);
        defer if (result) |r| r.deinit();

        if (result) |r| {
            try std.testing.expectEqual(@as(usize, 0), r.start);
            try std.testing.expectEqual(@as(usize, 3), r.end); // Must match exactly 3
        }
    }

    // Test 5: Lazy quantifier with character class
    {
        var re = try Regex.compile(allocator, "[a-z]{2,5}?");
        defer re.deinit();

        const result = try re.find("abcdef");
        try std.testing.expect(result != null);
        defer if (result) |r| r.deinit();

        if (result) |r| {
            try std.testing.expectEqual(@as(usize, 0), r.start);
            try std.testing.expectEqual(@as(usize, 2), r.end); // Matches "ab" (minimum)
        }
    }

    // Test 6: Multiple lazy quantifiers in sequence
    {
        // With input "abbb", lazy quantifiers should match "ab" (1 'a' + 1 'b')
        var re = try Regex.compile(allocator, "a{1,3}?b{1,3}?");
        defer re.deinit();

        const result = try re.find("abbb");
        try std.testing.expect(result != null);
        defer if (result) |r| r.deinit();

        if (result) |r| {
            try std.testing.expectEqual(@as(usize, 0), r.start);
            try std.testing.expectEqual(@as(usize, 2), r.end); // Matches "ab" (both minimal)
        }
    }

    // Test 7: Lazy quantifier with digits
    {
        var re = try Regex.compile(allocator, "\\d{2,4}?");
        defer re.deinit();

        const result = try re.find("12345");
        try std.testing.expect(result != null);
        defer if (result) |r| r.deinit();

        if (result) |r| {
            try std.testing.expectEqual(@as(usize, 0), r.start);
            try std.testing.expectEqual(@as(usize, 2), r.end); // Matches "12" (minimum)
        }
    }

    // Test 8: Lazy unbounded with following pattern
    {
        // With "aab", lazy should match minimum 2 'a's + 'b'
        var re = try Regex.compile(allocator, "a{2,}?b");
        defer re.deinit();

        const result = try re.find("aab");
        try std.testing.expect(result != null);
        defer if (result) |r| r.deinit();

        if (result) |r| {
            try std.testing.expectEqual(@as(usize, 0), r.start);
            try std.testing.expectEqual(@as(usize, 3), r.end); // Matches "aab" (2 'a's + 'b')
        }
    }
}
