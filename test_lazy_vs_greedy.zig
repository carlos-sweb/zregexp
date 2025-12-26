const std = @import("std");
const regex = @import("src/regex.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Lazy vs Greedy ===\n", .{});

    // Lazy version: a{2,}?b
    std.debug.print("\nLazy: a{{2,}}?b with 'aaaaab'\n", .{});
    var re_lazy = try regex.Regex.compile(allocator, "a{2,}?b");
    defer re_lazy.deinit();

    const result_lazy = try re_lazy.find("aaaaab");
    if (result_lazy) |r| {
        defer r.deinit();
        std.debug.print("MATCH at [{}, {}) = '{s}'\n", .{ r.start, r.end, "aaaaab"[r.start..r.end] });
    } else {
        std.debug.print("NO MATCH\n", .{});
    }

    // Greedy version: a{2,}b
    std.debug.print("\nGreedy: a{{2,}}b with 'aaaaab'\n", .{});
    var re_greedy = try regex.Regex.compile(allocator, "a{2,}b");
    defer re_greedy.deinit();

    const result_greedy = try re_greedy.find("aaaaab");
    if (result_greedy) |r| {
        defer r.deinit();
        std.debug.print("MATCH at [{}, {}) = '{s}'\n", .{ r.start, r.end, "aaaaab"[r.start..r.end] });
    } else {
        std.debug.print("NO MATCH\n", .{});
    }

    // Simple test: a{2}b
    std.debug.print("\nExact: a{{2}}b with 'aab'\n", .{});
    var re_exact = try regex.Regex.compile(allocator, "a{2}b");
    defer re_exact.deinit();

    const result_exact = try re_exact.find("aab");
    if (result_exact) |r| {
        defer r.deinit();
        std.debug.print("MATCH at [{}, {}) = '{s}'\n", .{ r.start, r.end, "aab"[r.start..r.end] });
    } else {
        std.debug.print("NO MATCH\n", .{});
    }
}
