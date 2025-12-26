//! Basic Usage Example
//!
//! This example demonstrates the fundamental usage of zregexp:
//! - Compiling a regex pattern
//! - Testing if a pattern matches
//! - Finding matches in text
//!
//! Build and run:
//!   zig build-exe basic_usage.zig --dep zregexp --mod zregexp:../src/main.zig
//!   ./basic_usage

const std = @import("std");
const zregexp = @import("zregexp");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== zregexp Basic Usage Example ===\n\n", .{});

    // Example 1: Simple pattern matching
    {
        std.debug.print("Example 1: Simple Pattern Matching\n", .{});
        std.debug.print("-----------------------------------\n", .{});

        var re = try zregexp.Regex.compile(allocator, "hello");
        defer re.deinit();

        const text1 = "hello world";
        const text2 = "goodbye world";

        std.debug.print("Pattern: '{}'\n", .{std.zig.fmtEscapes(re.getPattern())});
        std.debug.print("Text 1: '{}' -> Match: {}\n", .{
            std.zig.fmtEscapes(text1),
            try re.test_(text1),
        });
        std.debug.print("Text 2: '{}' -> Match: {}\n\n", .{
            std.zig.fmtEscapes(text2),
            try re.test_(text2),
        });
    }

    // Example 2: Finding matches in text
    {
        std.debug.print("Example 2: Finding Matches\n", .{});
        std.debug.print("--------------------------\n", .{});

        var re = try zregexp.Regex.compile(allocator, "world");
        defer re.deinit();

        const text = "hello world, beautiful world";
        std.debug.print("Pattern: '{}'\n", .{std.zig.fmtEscapes(re.getPattern())});
        std.debug.print("Text: '{}'\n", .{std.zig.fmtEscapes(text)});

        if (try re.find(text)) |match| {
            defer match.deinit();
            std.debug.print("First match found at position {}-{}\n", .{ match.start, match.end });
            std.debug.print("Matched text: '{}'\n\n", .{std.zig.fmtEscapes(match.group(text))});
        }
    }

    // Example 3: One-shot matching (convenience functions)
    {
        std.debug.print("Example 3: One-Shot Matching\n", .{});
        std.debug.print("-----------------------------\n", .{});

        const pattern = "quick";
        const text = "the quick brown fox";

        if (try zregexp.test_(allocator, pattern, text)) {
            std.debug.print("Pattern '{}' matches in '{}'\n\n", .{
                std.zig.fmtEscapes(pattern),
                std.zig.fmtEscapes(text),
            });
        }
    }

    // Example 4: Using metacharacters
    {
        std.debug.print("Example 4: Metacharacters\n", .{});
        std.debug.print("-------------------------\n", .{});

        var re = try zregexp.Regex.compile(allocator, "h.llo");
        defer re.deinit();

        const tests = [_][]const u8{ "hello", "hallo", "hxllo", "hllo" };

        std.debug.print("Pattern: '{}' (dot matches any character)\n", .{std.zig.fmtEscapes(re.getPattern())});
        for (tests) |test_text| {
            const matches = try re.test_(test_text);
            std.debug.print("  '{}' -> {}\n", .{ std.zig.fmtEscapes(test_text), matches });
        }
        std.debug.print("\n", .{});
    }

    // Example 5: Quantifiers
    {
        std.debug.print("Example 5: Quantifiers\n", .{});
        std.debug.print("----------------------\n", .{});

        const patterns = [_][]const u8{ "a*", "a+", "a?" };
        const tests = [_][]const u8{ "", "a", "aa", "aaa" };

        for (patterns) |pattern| {
            var re = try zregexp.Regex.compile(allocator, pattern);
            defer re.deinit();

            std.debug.print("Pattern: '{}'\n", .{std.zig.fmtEscapes(pattern)});
            for (tests) |test_text| {
                const matches = try re.test_(test_text);
                std.debug.print("  '{}' -> {}\n", .{ std.zig.fmtEscapes(test_text), matches });
            }
            std.debug.print("\n", .{});
        }
    }

    // Example 6: Anchors
    {
        std.debug.print("Example 6: Anchors\n", .{});
        std.debug.print("------------------\n", .{});

        var re = try zregexp.Regex.compile(allocator, "^hello$");
        defer re.deinit();

        const tests = [_][]const u8{ "hello", "hello world", "say hello", "hello there" };

        std.debug.print("Pattern: '{}' (must match entire string)\n", .{std.zig.fmtEscapes(re.getPattern())});
        for (tests) |test_text| {
            const matches = try re.test_(test_text);
            std.debug.print("  '{}' -> {}\n", .{ std.zig.fmtEscapes(test_text), matches });
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("=== Example Complete ===\n", .{});
}
