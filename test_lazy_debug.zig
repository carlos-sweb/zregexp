const std = @import("std");
const Regex = @import("src/regex.zig").Regex;
const compiler = @import("src/codegen/compiler.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test lazy star
    std.debug.print("\n=== Testing a*? ===\n", .{});

    // First, check what bytecode is generated
    const result = try compiler.compileSimple(allocator, "a*?");
    defer result.deinit();

    std.debug.print("Bytecode length: {} bytes\n", .{result.bytecode.len});

    // Now test matching
    var re = try Regex.compile(allocator, "a*?");
    defer re.deinit();

    const test1 = try re.test_("");
    std.debug.print("Test '' : {}\n", .{test1});

    const test2 = try re.test_("aaa");
    std.debug.print("Test 'aaa' : {}\n", .{test2});

    const match = try re.find("aaa");
    if (match) |m| {
        std.debug.print("Match: start={}, end={}\n", .{m.start, m.end});
    } else {
        std.debug.print("No match\n", .{});
    }
}
