const std = @import("std");
const regex = @import("src/regex.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Lazy Sequence ===\n", .{});

    // Test: a{1,3}?b{1,3}?
    std.debug.print("\nTest: a{{1,3}}?b{{1,3}}? with 'aaabbb'\n", .{});
    var re = try regex.Regex.compile(allocator, "a{1,3}?b{1,3}?");
    defer re.deinit();

    const result = try re.find("aaabbb");
    if (result) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "aaabbb"[r.start..r.end];
        std.debug.print("   Matched text: '{s}' (length: {})\n", .{ matched_text, matched_text.len });
        std.debug.print("   Expected: 'ab' (length: 2)\n", .{});
    } else {
        std.debug.print("❌ NO MATCH\n", .{});
    }

    // Test: a{1,3}?b (simpler case)
    std.debug.print("\nTest: a{{1,3}}?b with 'aaab'\n", .{});
    var re2 = try regex.Regex.compile(allocator, "a{1,3}?b");
    defer re2.deinit();

    const result2 = try re2.find("aaab");
    if (result2) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "aaab"[r.start..r.end];
        std.debug.print("   Matched text: '{s}' (length: {})\n", .{ matched_text, matched_text.len });
        std.debug.print("   Expected: 'aaab' (length: 4) - needs all 'a's to reach 'b'\n", .{});
    } else {
        std.debug.print("❌ NO MATCH\n", .{});
    }
}
