const std = @import("std");
const regex = @import("src/regex.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Lazy Star ===\n", .{});

    // Test: a*?b
    std.debug.print("\nTest: a*?b with 'aaab'\n", .{});
    var re = try regex.Regex.compile(allocator, "a*?b");
    defer re.deinit();

    const result = try re.find("aaab");
    if (result) |r| {
        defer r.deinit();
        std.debug.print("MATCH at [{}, {}) = '{s}'\n", .{ r.start, r.end, "aaab"[r.start..r.end] });
        std.debug.print("Expected: [0, 4) = 'aaab' (needs all 'a's to reach 'b')\n", .{});
    } else {
        std.debug.print("NO MATCH\n", .{});
    }

    // Test: a*?b with "b"
    std.debug.print("\nTest: a*?b with 'b'\n", .{});
    const result2 = try re.find("b");
    if (result2) |r| {
        defer r.deinit();
        std.debug.print("MATCH at [{}, {}) = '{s}'\n", .{ r.start, r.end, "b"[r.start..r.end] });
        std.debug.print("Expected: [0, 1) = 'b' (zero 'a's, lazy match)\n", .{});
    } else {
        std.debug.print("NO MATCH\n", .{});
    }
}
