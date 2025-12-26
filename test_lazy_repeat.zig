const std = @import("std");
const regex = @import("src/regex.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Lazy Counted Quantifiers ===\n", .{});

    // Test 1: Simple a{2,4}?
    std.debug.print("\nTest 1: a{{2,4}}? with 'aaaa'\n", .{});
    var re1 = try regex.Regex.compile(allocator, "a{2,4}?");
    defer re1.deinit();

    const result1 = try re1.find("aaaa");
    if (result1) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "aaaa"[r.start..r.end];
        std.debug.print("   Matched text: '{s}'\n", .{matched_text});
    } else {
        std.debug.print("❌ NO MATCH\n", .{});
    }

    // Test 2: a{2,}?
    std.debug.print("\nTest 2: a{{2,}}? with 'aaaaaa'\n", .{});
    var re2 = try regex.Regex.compile(allocator, "a{2,}?");
    defer re2.deinit();

    const result2 = try re2.find("aaaaaa");
    if (result2) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "aaaaaa"[r.start..r.end];
        std.debug.print("   Matched text: '{s}'\n", .{matched_text});
    } else {
        std.debug.print("❌ NO MATCH\n", .{});
    }

    // Test 3: The failing test - ".*?"
    std.debug.print("\nTest 3: \".*?\" with '\"hello\" and \"world\"'\n", .{});
    var re3 = try regex.Regex.compile(allocator, "\".*?\"");
    defer re3.deinit();

    const result3 = try re3.find("\"hello\" and \"world\"");
    if (result3) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "\"hello\" and \"world\""[r.start..r.end];
        std.debug.print("   Matched text: '{s}'\n", .{matched_text});
    } else {
        std.debug.print("❌ NO MATCH\n", .{});
    }
}
