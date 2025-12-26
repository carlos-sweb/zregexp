//! High-level matching API
//!
//! This module provides the main matching interface for compiled regex patterns.

const std = @import("std");
const Allocator = std.mem.Allocator;
const recursive_mod = @import("recursive_matcher.zig");
const thread_mod = @import("thread.zig");

const RecursiveMatcher = recursive_mod.RecursiveMatcher;
const Capture = thread_mod.Capture;

/// Match result
pub const MatchResult = struct {
    matched: bool,
    start: usize,
    end: usize,
    captures: []Capture,
    allocator: Allocator,

    /// Free match result
    pub fn deinit(self: MatchResult) void {
        self.allocator.free(self.captures);
    }

    /// Get full matched string
    pub fn group(self: MatchResult, input: []const u8) []const u8 {
        if (!self.matched) return "";
        return input[self.start..self.end];
    }

    /// Get capture group by index
    pub fn getCapture(self: MatchResult, index: usize, input: []const u8) ?[]const u8 {
        if (!self.matched or index >= self.captures.len) return null;
        const cap = self.captures[index];
        if (!cap.isValid()) return null;
        return input[cap.start.?..cap.end.?];
    }
};

/// Main matcher interface
pub const Matcher = struct {
    allocator: Allocator,
    bytecode: []const u8,

    const Self = @This();

    /// Initialize matcher with compiled bytecode
    pub fn init(allocator: Allocator, bytecode: []const u8) Self {
        return .{
            .allocator = allocator,
            .bytecode = bytecode,
        };
    }

    /// Check if pattern matches entire input
    pub fn matchFull(self: Self, input: []const u8) !bool {
        var matcher = RecursiveMatcher.init(self.allocator, self.bytecode, input);

        const result = try matcher.matchFrom(0, 0);

        // For full match, verify that the entire input was consumed
        return result.matched and result.end_pos == input.len;
    }

    /// Find first match in input
    pub fn find(self: Self, input: []const u8) !?MatchResult {
        // Try matching from each position
        var start_pos: usize = 0;
        while (start_pos <= input.len) : (start_pos += 1) {
            // Pass the FULL input to matcher (not a slice)
            // This allows lookbehind to see content before start_pos
            var matcher = RecursiveMatcher.init(self.allocator, self.bytecode, input);

            // Start matching from start_pos in the full input
            const result = try matcher.matchFrom(0, start_pos);
            if (result.matched) {
                // Found a match!
                // Copy captures (positions are already relative to original input)
                const captures = try self.allocator.alloc(Capture, 16);
                for (0..16) |i| {
                    captures[i] = Capture{
                        .start = result.captures[i].start,
                        .end = result.captures[i].end,
                    };
                }

                return MatchResult{
                    .matched = true,
                    .start = start_pos,
                    .end = result.end_pos,
                    .captures = captures,
                    .allocator = self.allocator,
                };
            }
        }

        return null;
    }

    /// Find all matches in input
    pub fn findAll(self: Self, input: []const u8) !std.ArrayListUnmanaged(MatchResult) {
        var matches = std.ArrayListUnmanaged(MatchResult){};
        errdefer {
            for (matches.items) |match| {
                match.deinit();
            }
            matches.deinit(self.allocator);
        }

        var pos: usize = 0;
        while (pos < input.len) {
            // Pass the FULL input to matcher (not a slice)
            // This allows lookbehind to see content before pos
            var matcher = RecursiveMatcher.init(self.allocator, self.bytecode, input);

            // Start matching from pos in the full input
            const result = try matcher.matchFrom(0, pos);
            if (result.matched) {
                // Copy captures (positions are already relative to original input)
                const captures = try self.allocator.alloc(Capture, 16);
                for (0..16) |i| {
                    captures[i] = Capture{
                        .start = result.captures[i].start,
                        .end = result.captures[i].end,
                    };
                }

                const match_result = MatchResult{
                    .matched = true,
                    .start = pos,
                    .end = result.end_pos,
                    .captures = captures,
                    .allocator = self.allocator,
                };

                try matches.append(self.allocator, match_result);

                // Advance past this match
                const match_len = result.end_pos - pos;
                pos = pos + match_len;
                if (match_len == 0) {
                    // Empty match, advance by 1 to avoid infinite loop
                    pos += 1;
                }
            } else {
                // No match at this position, try next
                pos += 1;
            }
        }

        return matches;
    }

    /// Test if pattern matches at start of input
    pub fn test_(self: Self, input: []const u8) !bool {
        return self.matchFull(input);
    }
};

// =============================================================================
// Tests
// =============================================================================

test "Matcher: matchFull success" {
    const compiler = @import("../codegen/compiler.zig");

    const compiled = try compiler.compileSimple(std.testing.allocator, "hello");
    defer compiled.deinit();

    const matcher = Matcher.init(std.testing.allocator, compiled.bytecode);
    const result = try matcher.matchFull("hello");

    try std.testing.expect(result);
}

test "Matcher: matchFull failure" {
    const compiler = @import("../codegen/compiler.zig");

    const compiled = try compiler.compileSimple(std.testing.allocator, "hello");
    defer compiled.deinit();

    const matcher = Matcher.init(std.testing.allocator, compiled.bytecode);
    const result = try matcher.matchFull("world");

    try std.testing.expect(!result);
}

test "Matcher: find match" {
    const compiler = @import("../codegen/compiler.zig");

    const compiled = try compiler.compileSimple(std.testing.allocator, "world");
    defer compiled.deinit();

    const matcher = Matcher.init(std.testing.allocator, compiled.bytecode);
    const result = try matcher.find("hello world");

    try std.testing.expect(result != null);
    defer result.?.deinit();

    try std.testing.expectEqual(@as(usize, 6), result.?.start);
    try std.testing.expectEqual(@as(usize, 11), result.?.end);
}

test "Matcher: find no match" {
    const compiler = @import("../codegen/compiler.zig");

    const compiled = try compiler.compileSimple(std.testing.allocator, "xyz");
    defer compiled.deinit();

    const matcher = Matcher.init(std.testing.allocator, compiled.bytecode);
    const result = try matcher.find("hello world");

    try std.testing.expect(result == null);
}

test "Matcher: find with capture" {
    const compiler = @import("../codegen/compiler.zig");

    const compiled = try compiler.compileSimple(std.testing.allocator, "(wo..)");
    defer compiled.deinit();

    const matcher = Matcher.init(std.testing.allocator, compiled.bytecode);
    const result = try matcher.find("hello world");

    try std.testing.expect(result != null);
    defer result.?.deinit();

    const captured = result.?.getCapture(1, "hello world");
    try std.testing.expect(captured != null);
    try std.testing.expectEqualStrings("worl", captured.?);
}

test "Matcher: findAll multiple matches" {
    const compiler = @import("../codegen/compiler.zig");

    const compiled = try compiler.compileSimple(std.testing.allocator, "a");
    defer compiled.deinit();

    const matcher = Matcher.init(std.testing.allocator, compiled.bytecode);
    var matches = try matcher.findAll("banana");
    defer {
        for (matches.items) |match| {
            match.deinit();
        }
        matches.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), matches.items.len);
    try std.testing.expectEqual(@as(usize, 1), matches.items[0].start);
    try std.testing.expectEqual(@as(usize, 3), matches.items[1].start);
    try std.testing.expectEqual(@as(usize, 5), matches.items[2].start);
}

test "Matcher: findAll no matches" {
    const compiler = @import("../codegen/compiler.zig");

    const compiled = try compiler.compileSimple(std.testing.allocator, "x");
    defer compiled.deinit();

    const matcher = Matcher.init(std.testing.allocator, compiled.bytecode);
    var matches = try matcher.findAll("hello");
    defer matches.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), matches.items.len);
}

test "Matcher: test_ function" {
    const compiler = @import("../codegen/compiler.zig");

    const compiled = try compiler.compileSimple(std.testing.allocator, "test");
    defer compiled.deinit();

    const matcher = Matcher.init(std.testing.allocator, compiled.bytecode);

    try std.testing.expect(try matcher.test_("test"));
    try std.testing.expect(!try matcher.test_("fail"));
}
