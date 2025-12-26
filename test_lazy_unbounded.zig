const std = @import("std");
const regex = @import("src/regex.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Lazy Unbounded ===\n", .{});

    // Test: a{2,}?b
    std.debug.print("\nTest: a{{2,}}?b with 'aaaaab'\n", .{});
    var re = try regex.Regex.compile(allocator, "a{2,}?b");
    defer re.deinit();

    const result = try re.find("aaaaab");
    if (result) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "aaaaab"[r.start..r.end];
        std.debug.print("   Matched text: '{s}' (length: {})\n", .{ matched_text, matched_text.len });
        std.debug.print("   Expected start: 0, got: {}\n", .{r.start});
        std.debug.print("   Expected end: 6, got: {}\n", .{r.end});
    } else {
        std.debug.print("❌ NO MATCH\n", .{});
    }
}
