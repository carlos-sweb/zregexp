const std = @import("std");
const regex = @import("src/regex.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Quick Test: Lazy Counted Quantifiers ===\n\n", .{});

    // Test 1: a{2,4}? - should match minimum
    {
        std.debug.print("Test 1: a{{2,4}}? with 'aaaa'\n", .{});
        var re = try regex.Regex.compile(allocator, "a{2,4}?");
        defer re.deinit();

        const result = try re.find("aaaa");
        if (result) |r| {
            defer r.deinit();
            const match = "aaaa"[r.start..r.end];
            std.debug.print("  ✅ Matched: '{s}' at [{}, {})\n", .{match, r.start, r.end});
            if (r.end - r.start == 2) {
                std.debug.print("  ✅ PASS - matched minimum (2)\n", .{});
            } else {
                std.debug.print("  ❌ FAIL - expected 2, got {}\n", .{r.end - r.start});
            }
        } else {
            std.debug.print("  ❌ FAIL - no match\n", .{});
        }
    }

    // Test 2: a{2,}? - unbounded lazy
    {
        std.debug.print("\nTest 2: a{{2,}}? with 'aaaaaa'\n", .{});
        var re = try regex.Regex.compile(allocator, "a{2,}?");
        defer re.deinit();

        const result = try re.find("aaaaaa");
        if (result) |r| {
            defer r.deinit();
            const match = "aaaaaa"[r.start..r.end];
            std.debug.print("  ✅ Matched: '{s}' at [{}, {})\n", .{match, r.start, r.end});
            if (r.end - r.start == 2) {
                std.debug.print("  ✅ PASS - matched minimum (2)\n", .{});
            } else {
                std.debug.print("  ❌ FAIL - expected 2, got {}\n", .{r.end - r.start});
            }
        } else {
            std.debug.print("  ❌ FAIL - no match\n", .{});
        }
    }

    // Test 3: a{3}? - exact count with lazy (same as greedy)
    {
        std.debug.print("\nTest 3: a{{3}}? with 'aaaaa'\n", .{});
        var re = try regex.Regex.compile(allocator, "a{3}?");
        defer re.deinit();

        const result = try re.find("aaaaa");
        if (result) |r| {
            defer r.deinit();
            const match = "aaaaa"[r.start..r.end];
            std.debug.print("  ✅ Matched: '{s}' at [{}, {})\n", .{match, r.start, r.end});
            if (r.end - r.start == 3) {
                std.debug.print("  ✅ PASS - matched exactly 3\n", .{});
            } else {
                std.debug.print("  ❌ FAIL - expected 3, got {}\n", .{r.end - r.start});
            }
        } else {
            std.debug.print("  ❌ FAIL - no match\n", .{});
        }
    }

    std.debug.print("\n=== All tests completed ===\n", .{});
}
