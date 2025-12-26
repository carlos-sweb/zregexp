const std = @import("std");
const regex = @import("src/regex.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Double Lookbehind ===\n", .{});

    // Test: (?<=a)(?<=ab)c with "abc"
    std.debug.print("\nTest: (?<=a)(?<=ab)c with 'abc'\n", .{});
    var re = try regex.Regex.compile(allocator, "(?<=a)(?<=ab)c");
    defer re.deinit();

    const result = try re.find("abc");
    if (result) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "abc"[r.start..r.end];
        std.debug.print("   Matched text: '{s}'\n", .{matched_text});
    } else {
        std.debug.print("❌ NO MATCH (expected a match!)\n", .{});
    }

    // Simpler test: just one lookbehind
    std.debug.print("\nTest: (?<=ab)c with 'abc'\n", .{});
    var re2 = try regex.Regex.compile(allocator, "(?<=ab)c");
    defer re2.deinit();

    const result2 = try re2.find("abc");
    if (result2) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "abc"[r.start..r.end];
        std.debug.print("   Matched text: '{s}'\n", .{matched_text});
    } else {
        std.debug.print("❌ NO MATCH (expected a match!)\n", .{});
    }
}
