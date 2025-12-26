//! Virtual Machine for executing regex bytecode
//!
//! This module implements the core VM that executes compiled regex bytecode,
//! handling instruction dispatch, character matching, and control flow.

const std = @import("std");
const Allocator = std.mem.Allocator;
const thread_mod = @import("thread.zig");
const opcodes = @import("../bytecode/opcodes.zig");
const format = @import("../bytecode/format.zig");
const reader = @import("../bytecode/reader.zig");

const Thread = thread_mod.Thread;
const ThreadQueue = thread_mod.ThreadQueue;
const Opcode = opcodes.Opcode;
const Instruction = format.Instruction;
const BytecodeReader = reader.BytecodeReader;

/// Thread state for visited tracking (prevents infinite loops in epsilon transitions)
pub const ThreadState = struct {
    pc: usize,  // Program counter
    sp: usize,  // String position

    /// Check equality
    pub fn eql(self: ThreadState, other: ThreadState) bool {
        return self.pc == other.pc and self.sp == other.sp;
    }

    /// Hash function for HashMap
    pub fn hash(self: ThreadState) u64 {
        var h = std.hash.Wyhash.init(0);
        std.hash.autoHash(&h, self.pc);
        std.hash.autoHash(&h, self.sp);
        return h.final();
    }
};

/// Context for HashMap (required by Zig's AutoHashMap)
pub const ThreadStateContext = struct {
    pub fn hash(_: ThreadStateContext, key: ThreadState) u64 {
        return key.hash();
    }

    pub fn eql(_: ThreadStateContext, a: ThreadState, b: ThreadState) bool {
        return a.eql(b);
    }
};

/// VM execution result
pub const ExecResult = struct {
    matched: bool,
    thread: ?Thread = null,

    /// Get capture group
    pub fn getCapture(self: ExecResult, group: usize, input: []const u8) ?[]const u8 {
        if (!self.matched or self.thread == null) return null;
        const cap = self.thread.?.getCapture(group) orelse return null;
        if (!cap.isValid()) return null;
        return input[cap.start.?..cap.end.?];
    }
};

/// Virtual Machine for regex execution
pub const VM = struct {
    allocator: Allocator,
    bytecode: []const u8,
    input: []const u8,
    current_queue: ThreadQueue,
    next_queue: ThreadQueue,
    visited: std.HashMap(ThreadState, void, ThreadStateContext, std.hash_map.default_max_load_percentage),

    const Self = @This();

    /// Initialize VM
    pub fn init(allocator: Allocator, bytecode: []const u8, input: []const u8) !Self {
        return .{
            .allocator = allocator,
            .bytecode = bytecode,
            .input = input,
            .current_queue = ThreadQueue.init(allocator),
            .next_queue = ThreadQueue.init(allocator),
            .visited = std.HashMap(ThreadState, void, ThreadStateContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.current_queue.deinit();
        self.next_queue.deinit();
        self.visited.deinit();
    }

    /// Execute bytecode and return match result
    pub fn execute(self: *Self) !ExecResult {
        // Start with initial thread at PC=0, SP=0
        const initial_thread = Thread.init(0, 0);
        try self.current_queue.add(initial_thread);

        // Track best match found so far (for greedy behavior)
        var best_match: ?ExecResult = null;

        // Process threads until no more remain
        while (true) {
            // Clear visited set for new iteration
            // This prevents infinite loops in epsilon transitions
            self.visited.clearRetainingCapacity();

            // Process all threads at current queue
            while (self.current_queue.pop()) |thread| {
                const result = try self.step(thread);

                if (result.matched) {
                    // Found a match - keep the longest one (greedy)
                    if (best_match == null or
                        (result.thread != null and best_match.?.thread != null and
                         result.thread.?.sp > best_match.?.thread.?.sp)) {
                        best_match = result;
                    }
                }
            }

            // If we found a match and no more threads, return best match
            if (best_match != null and self.next_queue.isEmpty()) {
                return best_match.?;
            }

            // Swap queues for next iteration
            std.mem.swap(ThreadQueue, &self.current_queue, &self.next_queue);
            self.next_queue.clear();

            // If no threads left, return best match found or no match
            if (self.current_queue.isEmpty()) {
                if (best_match) |bm| {
                    return bm;
                }
                return ExecResult{ .matched = false };
            }
        }
    }

    /// Execute one step for a thread
    fn step(self: *Self, thread: Thread) !ExecResult {
        var current = thread;

        // Keep executing until we need to advance string position
        while (true) {
            if (current.pc >= self.bytecode.len) {
                return ExecResult{ .matched = false };
            }

            const inst = try format.decodeInstruction(self.bytecode, current.pc);

            switch (inst.opcode) {
                .MATCH => {
                    // Successful match!
                    return ExecResult{ .matched = true, .thread = current };
                },

                .CHAR32 => {
                    // Match specific character
                    if (current.sp >= self.input.len) {
                        return ExecResult{ .matched = false };
                    }
                    const c = self.input[current.sp];
                    if (c == inst.operands[0]) {
                        // Matched, advance to next position
                        current.sp += 1;
                        current.pc += inst.size;
                        try self.next_queue.add(current);
                    }
                    return ExecResult{ .matched = false };
                },

                .CHAR => {
                    // Match any character (dot)
                    if (current.sp >= self.input.len) {
                        return ExecResult{ .matched = false };
                    }
                    current.sp += 1;
                    current.pc += inst.size;
                    try self.next_queue.add(current);
                    return ExecResult{ .matched = false };
                },

                .CHAR_RANGE => {
                    // Match character in range
                    if (current.sp >= self.input.len) {
                        return ExecResult{ .matched = false };
                    }
                    const c = self.input[current.sp];
                    const min = @as(u8, @intCast(inst.operands[0]));
                    const max = @as(u8, @intCast(inst.operands[1]));
                    if (c >= min and c <= max) {
                        current.sp += 1;
                        current.pc += inst.size;
                        try self.next_queue.add(current);
                    }
                    return ExecResult{ .matched = false };
                },

                .GOTO => {
                    // Unconditional jump
                    const offset = @as(i32, @bitCast(inst.operands[0]));
                    const new_pc: usize = @intCast(@as(i32, @intCast(current.pc)) + offset);

                    // Check for infinite loop: if we're jumping back to same state we visited
                    const state = ThreadState{ .pc = new_pc, .sp = current.sp };
                    if (self.visited.contains(state)) {
                        // Would create infinite loop, stop this thread
                        return ExecResult{ .matched = false };
                    }
                    try self.visited.put(state, {});

                    current.pc = new_pc;
                    // Continue execution in same step
                },

                .SPLIT, .SPLIT_GREEDY, .SPLIT_LAZY => {
                    // Fork execution
                    const offset1 = @as(i32, @bitCast(inst.operands[0]));
                    const offset2 = @as(i32, @bitCast(inst.operands[1]));

                    const pc1: usize = @intCast(@as(i32, @intCast(current.pc)) + offset1);
                    const pc2: usize = @intCast(@as(i32, @intCast(current.pc)) + offset2);

                    // Create second thread and add to queue
                    var thread2 = current.clone();
                    thread2.pc = pc2;
                    try self.current_queue.add(thread2);

                    // Continue with first thread immediately (avoid adding to queue to prevent infinite loop)
                    current.pc = pc1;
                    // Continue execution in same step
                },

                .SAVE_START => {
                    // Save capture start
                    const group = @as(usize, @intCast(inst.operands[0]));
                    current.saveStart(group, current.sp);
                    current.pc += inst.size;
                    // Continue execution
                },

                .SAVE_END => {
                    // Save capture end
                    const group = @as(usize, @intCast(inst.operands[0]));
                    current.saveEnd(group, current.sp);
                    current.pc += inst.size;
                    // Continue execution
                },

                .LINE_START => {
                    // Assert start of line
                    if (current.sp != 0) {
                        return ExecResult{ .matched = false };
                    }
                    current.pc += inst.size;
                    // Continue execution
                },

                .LINE_END => {
                    // Assert end of line
                    if (current.sp != self.input.len) {
                        return ExecResult{ .matched = false };
                    }
                    current.pc += inst.size;
                    // Continue execution
                },

                .WORD_BOUNDARY => {
                    // Assert word boundary
                    if (!self.isWordBoundary(current.sp)) {
                        return ExecResult{ .matched = false };
                    }
                    current.pc += inst.size;
                    // Continue execution
                },

                .NOT_WORD_BOUNDARY => {
                    // Assert not word boundary
                    if (self.isWordBoundary(current.sp)) {
                        return ExecResult{ .matched = false };
                    }
                    current.pc += inst.size;
                    // Continue execution
                },

                else => {
                    // Unsupported opcode
                    return ExecResult{ .matched = false };
                },
            }
        }
    }

    /// Check if position is at word boundary
    fn isWordBoundary(self: Self, pos: usize) bool {
        const before_is_word = if (pos > 0) isWordChar(self.input[pos - 1]) else false;
        const after_is_word = if (pos < self.input.len) isWordChar(self.input[pos]) else false;
        return before_is_word != after_is_word;
    }

    /// Check if character is word character
    fn isWordChar(c: u8) bool {
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '_';
    }
};

// =============================================================================
// Tests
// =============================================================================

test "VM: simple character match" {
    const compiler = @import("../codegen/compiler.zig");

    const result = try compiler.compileSimple(std.testing.allocator, "a");
    defer result.deinit();

    var vm = try VM.init(std.testing.allocator, result.bytecode, "a");
    defer vm.deinit();

    const exec_result = try vm.execute();
    try std.testing.expect(exec_result.matched);
}

test "VM: simple character no match" {
    const compiler = @import("../codegen/compiler.zig");

    const result = try compiler.compileSimple(std.testing.allocator, "a");
    defer result.deinit();

    var vm = try VM.init(std.testing.allocator, result.bytecode, "b");
    defer vm.deinit();

    const exec_result = try vm.execute();
    try std.testing.expect(!exec_result.matched);
}

test "VM: sequence match" {
    const compiler = @import("../codegen/compiler.zig");

    const result = try compiler.compileSimple(std.testing.allocator, "abc");
    defer result.deinit();

    var vm = try VM.init(std.testing.allocator, result.bytecode, "abc");
    defer vm.deinit();

    const exec_result = try vm.execute();
    try std.testing.expect(exec_result.matched);
}

test "VM: dot matches any character" {
    const compiler = @import("../codegen/compiler.zig");

    const result = try compiler.compileSimple(std.testing.allocator, ".");
    defer result.deinit();

    var vm = try VM.init(std.testing.allocator, result.bytecode, "x");
    defer vm.deinit();

    const exec_result = try vm.execute();
    try std.testing.expect(exec_result.matched);
}

test "VM: alternation" {
    const compiler = @import("../codegen/compiler.zig");

    const result = try compiler.compileSimple(std.testing.allocator, "a|b");
    defer result.deinit();

    {
        var vm = try VM.init(std.testing.allocator, result.bytecode, "a");
        defer vm.deinit();
        const exec_result = try vm.execute();
        try std.testing.expect(exec_result.matched);
    }

    {
        var vm = try VM.init(std.testing.allocator, result.bytecode, "b");
        defer vm.deinit();
        const exec_result = try vm.execute();
        try std.testing.expect(exec_result.matched);
    }
}

test "VM: capture group" {
    const compiler = @import("../codegen/compiler.zig");

    const result = try compiler.compileSimple(std.testing.allocator, "(ab)");
    defer result.deinit();

    var vm = try VM.init(std.testing.allocator, result.bytecode, "ab");
    defer vm.deinit();

    const exec_result = try vm.execute();
    try std.testing.expect(exec_result.matched);

    const captured = exec_result.getCapture(1, "ab");
    try std.testing.expect(captured != null);
    try std.testing.expectEqualStrings("ab", captured.?);
}

test "VM: anchor start" {
    const compiler = @import("../codegen/compiler.zig");

    const result = try compiler.compileSimple(std.testing.allocator, "^a");
    defer result.deinit();

    {
        var vm = try VM.init(std.testing.allocator, result.bytecode, "a");
        defer vm.deinit();
        const exec_result = try vm.execute();
        try std.testing.expect(exec_result.matched);
    }

    {
        var vm = try VM.init(std.testing.allocator, result.bytecode, "ba");
        defer vm.deinit();
        const exec_result = try vm.execute();
        try std.testing.expect(!exec_result.matched);
    }
}

test "VM: anchor end" {
    const compiler = @import("../codegen/compiler.zig");

    const result = try compiler.compileSimple(std.testing.allocator, "a$");
    defer result.deinit();

    {
        var vm = try VM.init(std.testing.allocator, result.bytecode, "a");
        defer vm.deinit();
        const exec_result = try vm.execute();
        try std.testing.expect(exec_result.matched);
    }

    {
        var vm = try VM.init(std.testing.allocator, result.bytecode, "ab");
        defer vm.deinit();
        const exec_result = try vm.execute();
        try std.testing.expect(!exec_result.matched);
    }
}
