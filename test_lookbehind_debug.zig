const std = @import("std");
const regex = @import("src/regex.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Basic Lookbehind ===\n", .{});

    // Test 1: Simple lookbehind
    std.debug.print("\nTest 1: (?<=\\$)\\d+ with 'Price: $100'\n", .{});
    var re = try regex.Regex.compile(allocator, "(?<=\\$)\\d+");
    defer re.deinit();

    const result = try re.find("Price: $100");
    if (result) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "Price: $100"[r.start..r.end];
        std.debug.print("   Matched text: '{s}'\n", .{matched_text});
    } else {
        std.debug.print("❌ NO MATCH (expected a match!)\n", .{});
    }

    // Test 2: Simpler test - just the $ and digits
    std.debug.print("\nTest 2: (?<=\\$)\\d+ with '$100'\n", .{});
    const result2 = try re.find("$100");
    if (result2) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "$100"[r.start..r.end];
        std.debug.print("   Matched text: '{s}'\n", .{matched_text});
    } else {
        std.debug.print("❌ NO MATCH (expected a match!)\n", .{});
    }

    // Test 3: Even simpler - just lookbehind for one char
    std.debug.print("\nTest 3: (?<=a)b with 'ab'\n", .{});
    var re3 = try regex.Regex.compile(allocator, "(?<=a)b");
    defer re3.deinit();

    const result3 = try re3.find("ab");
    if (result3) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "ab"[r.start..r.end];
        std.debug.print("   Matched text: '{s}'\n", .{matched_text});
    } else {
        std.debug.print("❌ NO MATCH (expected a match!)\n", .{});
    }

    // Test 4: Without lookbehind - just to verify basic regex works
    std.debug.print("\nTest 4: \\$\\d+ with '$100' (no lookbehind)\n", .{});
    var re4 = try regex.Regex.compile(allocator, "\\$\\d+");
    defer re4.deinit();

    const result4 = try re4.find("$100");
    if (result4) |r| {
        defer r.deinit();
        std.debug.print("✅ MATCH found at [{}, {})\n", .{ r.start, r.end });
        const matched_text = "$100"[r.start..r.end];
        std.debug.print("   Matched text: '{s}'\n", .{matched_text});
    } else {
        std.debug.print("❌ NO MATCH\n", .{});
    }
}
