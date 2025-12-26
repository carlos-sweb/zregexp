//! Recursive regex matcher with backtracking
//!
//! This module implements a recursive matching engine inspired by mvzr,
//! replacing the Pike VM approach to solve the SPLIT infinite loop bug.
//!
//! Key advantages:
//! - No visited set needed (recursion naturally bounds loops)
//! - Simple backtracking logic
//! - Greedy quantifiers work correctly
//! - Easy to debug (language stack traces)

const std = @import("std");
const Allocator = std.mem.Allocator;
const opcodes = @import("../bytecode/opcodes.zig");
const format = @import("../bytecode/format.zig");

const Opcode = opcodes.Opcode;
const Instruction = format.Instruction;

/// Maximum number of capture groups supported
const MAX_CAPTURE_GROUPS = 16;

/// Default maximum recursion depth (protects against stack overflow)
pub const DEFAULT_MAX_RECURSION_DEPTH: usize = 1000;

/// Default maximum execution steps (protects against ReDoS)
pub const DEFAULT_MAX_STEPS: usize = 1_000_000;

/// Execution options for ReDoS protection
pub const ExecOptions = struct {
    /// Maximum recursion depth (0 = unlimited, not recommended)
    max_recursion_depth: usize = DEFAULT_MAX_RECURSION_DEPTH,

    /// Maximum execution steps (0 = unlimited, not recommended)
    max_steps: usize = DEFAULT_MAX_STEPS,

    /// Create options with unlimited limits (dangerous!)
    pub fn unlimited() ExecOptions {
        return .{
            .max_recursion_depth = 0,
            .max_steps = 0,
        };
    }

    /// Create options with custom limits
    pub fn withLimits(max_recursion: usize, max_steps: usize) ExecOptions {
        return .{
            .max_recursion_depth = max_recursion,
            .max_steps = max_steps,
        };
    }
};

/// Match result
pub const MatchResult = struct {
    matched: bool,
    end_pos: usize,

    /// Capture groups (index 0 = whole match)
    captures: [MAX_CAPTURE_GROUPS]CaptureGroup = [_]CaptureGroup{.{}} ** MAX_CAPTURE_GROUPS,

    /// Get capture group by index
    pub fn getCapture(self: MatchResult, group: usize, input: []const u8) ?[]const u8 {
        if (group >= MAX_CAPTURE_GROUPS) return null;
        const cap = self.captures[group];
        if (!cap.isValid()) return null;
        return input[cap.start.?..cap.end.?];
    }
};

/// Capture group boundaries
pub const CaptureGroup = struct {
    start: ?usize = null,
    end: ?usize = null,

    pub fn isValid(self: CaptureGroup) bool {
        return self.start != null and self.end != null;
    }
};

/// Recursive matcher
pub const RecursiveMatcher = struct {
    allocator: Allocator,
    bytecode: []const u8,
    input: []const u8,
    captures: [MAX_CAPTURE_GROUPS]CaptureGroup,
    recursion_depth: usize,
    step_count: usize,
    exec_options: ExecOptions,

    const Self = @This();

    /// Error set for matching operations
    pub const MatchError = error{ OutOfMemory, UnknownOpcode, UnexpectedEndOfBytecode, RecursionLimitExceeded, StepLimitExceeded };

    pub fn init(allocator: Allocator, bytecode: []const u8, input: []const u8) Self {
        return Self.initWithOptions(allocator, bytecode, input, ExecOptions{});
    }

    pub fn initWithOptions(allocator: Allocator, bytecode: []const u8, input: []const u8, options: ExecOptions) Self {
        return .{
            .allocator = allocator,
            .bytecode = bytecode,
            .input = input,
            .captures = [_]CaptureGroup{.{}} ** MAX_CAPTURE_GROUPS,
            .recursion_depth = 0,
            .step_count = 0,
            .exec_options = options,
        };
    }

    /// Match from specific PC and string position
    pub fn matchFrom(self: *Self, pc: usize, pos: usize) error{ OutOfMemory, UnknownOpcode, UnexpectedEndOfBytecode, RecursionLimitExceeded, StepLimitExceeded }!MatchResult {
        // Check step limit (protects against ReDoS)
        if (self.exec_options.max_steps > 0) {
            self.step_count += 1;
            if (self.step_count >= self.exec_options.max_steps) {
                return error.StepLimitExceeded;
            }
        }

        // Check recursion depth limit (protects against stack overflow)
        if (self.exec_options.max_recursion_depth > 0) {
            if (self.recursion_depth >= self.exec_options.max_recursion_depth) {
                return error.RecursionLimitExceeded;
            }
        }

        self.recursion_depth += 1;
        defer self.recursion_depth -= 1;

        // Check bounds
        if (pc >= self.bytecode.len) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }

        const inst = try format.decodeInstruction(self.bytecode, pc);

        switch (inst.opcode) {
            .MATCH => {
                // Success!
                var result = MatchResult{
                    .matched = true,
                    .end_pos = pos,
                };
                result.captures = self.captures;
                return result;
            },

            .CHAR32 => {
                // Match specific character
                const expected = @as(u8, @intCast(inst.operands[0]));
                return self.matchChar(pc, pos, expected, inst.size);
            },

            .CHAR => {
                // Match any character (dot)
                if (pos >= self.input.len) {
                    return MatchResult{ .matched = false, .end_pos = pos };
                }
                return self.matchFrom(pc + inst.size, pos + 1);
            },

            .CHAR_RANGE => {
                // Match character in range [min, max]
                const min = @as(u8, @intCast(inst.operands[0]));
                const max = @as(u8, @intCast(inst.operands[1]));
                return self.matchCharRange(pc, pos, min, max, inst.size);
            },

            .CHAR_RANGE_INV => {
                // Match character NOT in range [^min-max]
                const min = @as(u8, @intCast(inst.operands[0]));
                const max = @as(u8, @intCast(inst.operands[1]));
                return self.matchCharRangeInv(pc, pos, min, max, inst.size);
            },

            .CHAR_CLASS => {
                // Match character in class (using bit table)
                // Table is stored inline: 32 bytes starting at pc + 1
                if (pc + 33 > self.bytecode.len) return error.UnexpectedEndOfBytecode;
                const table = self.bytecode[pc + 1 ..][0..32];
                return self.matchCharClass(pc, pos, table, inst.size);
            },

            .CHAR_CLASS_INV => {
                // Match character NOT in class (using bit table)
                // Table is stored inline: 32 bytes starting at pc + 1
                if (pc + 33 > self.bytecode.len) return error.UnexpectedEndOfBytecode;
                const table = self.bytecode[pc + 1 ..][0..32];
                return self.matchCharClassInv(pc, pos, table, inst.size);
            },

            .GOTO => {
                // Unconditional jump
                const offset = @as(i32, @bitCast(inst.operands[0]));
                const new_pc: usize = @intCast(@as(i32, @intCast(pc)) + offset);
                return self.matchFrom(new_pc, pos);
            },

            .SPLIT, .SPLIT_GREEDY, .SPLIT_LAZY, .SPLIT_POSSESSIVE => {
                // Fork execution (used for quantifiers and alternation)
                const offset1 = @as(i32, @bitCast(inst.operands[0]));
                const offset2 = @as(i32, @bitCast(inst.operands[1]));

                // Special handling: offset=0 means "fall through to next instruction"
                const pc1: usize = if (offset1 == 0)
                    pc + inst.size
                else
                    @intCast(@as(i32, @intCast(pc)) + offset1);

                const pc2: usize = if (offset2 == 0)
                    pc + inst.size
                else
                    @intCast(@as(i32, @intCast(pc)) + offset2);

                // Check if possessive (no backtracking)
                const is_possessive = (inst.opcode == .SPLIT_POSSESSIVE);

                // Detect pattern type by analyzing what follows
                const is_star = try self.isStarQuantifier(pc, pc1, pc2);

                if (is_star) {
                    // Determine which path is consume and which is skip
                    const pc1_is_consume = try self.isStarConsumePath(pc, pc1);
                    const pc_consume = if (pc1_is_consume) pc1 else pc2;
                    const pc_skip = if (pc1_is_consume) pc2 else pc1;

                    if (is_possessive) {
                        // Possessive: consume all without backtracking
                        return self.matchStarPossessive(pc_consume, pc_skip, pos);
                    } else {
                        // Determine greediness: greedy by default, lazy only if explicitly SPLIT_LAZY
                        const greedy = (inst.opcode != .SPLIT_LAZY);
                        // This is a star quantifier: try both paths with backtracking
                        return self.matchStar(pc_consume, pc_skip, pos, greedy);
                    }
                } else {
                    // Check if it's a question quantifier
                    const is_question = try self.isQuestionQuantifier(pc1, pc2);

                    if (is_possessive) {
                        // Possessive: try greedy path once, no backtracking
                        const result1 = try self.matchFrom(pc1, pos);
                        if (result1.matched) {
                            return result1;
                        }
                        // Only try second path if first failed
                        return self.matchFrom(pc2, pos);
                    } else if (is_question) {
                        // Question quantifier: try both paths and prefer longer match
                        const greedy = (inst.opcode != .SPLIT_LAZY);

                        const result1 = try self.matchFrom(pc1, pos);
                        const result2 = try self.matchFrom(pc2, pos);

                        // Both failed
                        if (!result1.matched and !result2.matched) {
                            return MatchResult{ .matched = false, .end_pos = pos };
                        }

                        // Only one succeeded
                        if (result1.matched and !result2.matched) return result1;
                        if (result2.matched and !result1.matched) return result2;

                        // Both succeeded: prefer based on greediness
                        if (greedy) {
                            // Greedy: prefer longer match
                            return if (result2.end_pos > result1.end_pos) result2 else result1;
                        } else {
                            // Lazy: prefer shorter match
                            return if (result1.end_pos < result2.end_pos) result1 else result2;
                        }
                    } else {
                        // Regular alternation: try first path, backtrack to second if needed
                        // This prevents infinite loops by using proper backtracking
                        const result1 = try self.matchFrom(pc1, pos);
                        if (result1.matched) {
                            return result1;
                        }

                        // First path failed, try second path
                        return self.matchFrom(pc2, pos);
                    }
                }
            },

            .SAVE_START => {
                // Save capture group start
                const group = @as(usize, @intCast(inst.operands[0]));
                if (group < MAX_CAPTURE_GROUPS) {
                    self.captures[group].start = pos;
                }
                return self.matchFrom(pc + inst.size, pos);
            },

            .SAVE_END => {
                // Save capture group end
                const group = @as(usize, @intCast(inst.operands[0]));
                if (group < MAX_CAPTURE_GROUPS) {
                    self.captures[group].end = pos;
                }
                return self.matchFrom(pc + inst.size, pos);
            },

            .BACK_REF => {
                // Match backreference to capture group (case-sensitive)
                const group = @as(usize, @intCast(inst.operands[0]));
                return self.matchBackRef(pc, pos, group, false, inst.size);
            },

            .BACK_REF_I => {
                // Match backreference to capture group (case-insensitive)
                const group = @as(usize, @intCast(inst.operands[0]));
                return self.matchBackRef(pc, pos, group, true, inst.size);
            },

            .LOOKAHEAD => {
                // Positive lookahead - assert pattern matches without consuming
                return self.matchLookahead(pc, pos, false, inst.size);
            },

            .NEGATIVE_LOOKAHEAD => {
                // Negative lookahead - assert pattern does NOT match
                return self.matchLookahead(pc, pos, true, inst.size);
            },

            .LOOKAHEAD_END => {
                // End of lookahead body - this is like MATCH but for lookahead patterns
                // We consider the lookahead pattern as successfully matched
                return MatchResult{
                    .matched = true,
                    .end_pos = pos,
                    .captures = self.captures,
                };
            },

            .LOOKBEHIND => {
                // Positive lookbehind - assert pattern matches behind current position
                return self.matchLookbehind(pc, pos, false, inst.size);
            },

            .NEGATIVE_LOOKBEHIND => {
                // Negative lookbehind - assert pattern does NOT match behind
                return self.matchLookbehind(pc, pos, true, inst.size);
            },

            .LOOKBEHIND_END => {
                // End of lookbehind body - this is like MATCH but for lookbehind patterns
                return MatchResult{
                    .matched = true,
                    .end_pos = pos,
                    .captures = self.captures,
                };
            },

            .LINE_START => {
                // Assert start of line
                if (pos != 0) {
                    return MatchResult{ .matched = false, .end_pos = pos };
                }
                return self.matchFrom(pc + inst.size, pos);
            },

            .LINE_END => {
                // Assert end of line
                if (pos != self.input.len) {
                    return MatchResult{ .matched = false, .end_pos = pos };
                }
                return self.matchFrom(pc + inst.size, pos);
            },

            .WORD_BOUNDARY => {
                // Assert word boundary
                if (!self.isWordBoundary(pos)) {
                    return MatchResult{ .matched = false, .end_pos = pos };
                }
                return self.matchFrom(pc + inst.size, pos);
            },

            .NOT_WORD_BOUNDARY => {
                // Assert NOT word boundary
                if (self.isWordBoundary(pos)) {
                    return MatchResult{ .matched = false, .end_pos = pos };
                }
                return self.matchFrom(pc + inst.size, pos);
            },

            else => {
                // Unsupported opcode
                return MatchResult{ .matched = false, .end_pos = pos };
            },
        }
    }

    /// Match specific character
    fn matchChar(self: *Self, pc: usize, pos: usize, expected: u8, inst_size: usize) MatchError!MatchResult {
        if (pos >= self.input.len) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
        if (self.input[pos] != expected) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
        // Continue with next instruction
        return self.matchFrom(pc + inst_size, pos + 1);
    }

    /// Match character in range
    fn matchCharRange(self: *Self, pc: usize, pos: usize, min: u8, max: u8, inst_size: usize) MatchError!MatchResult {
        if (pos >= self.input.len) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
        const c = self.input[pos];
        if (c < min or c > max) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
        return self.matchFrom(pc + inst_size, pos + 1);
    }

    /// Match character NOT in range (inverted)
    fn matchCharRangeInv(self: *Self, pc: usize, pos: usize, min: u8, max: u8, inst_size: usize) MatchError!MatchResult {
        if (pos >= self.input.len) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
        const c = self.input[pos];
        // Inverted logic: match if NOT in range
        if (c >= min and c <= max) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
        return self.matchFrom(pc + inst_size, pos + 1);
    }

    /// Match character in class (using bit table)
    fn matchCharClass(self: *Self, pc: usize, pos: usize, table: *const [32]u8, inst_size: usize) MatchError!MatchResult {
        if (pos >= self.input.len) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
        const c = self.input[pos];

        // Check if character is in the bit table
        const byte_idx = c / 8;
        const bit_idx = @as(u3, @intCast(c % 8));
        const is_in_class = (table[byte_idx] & (@as(u8, 1) << bit_idx)) != 0;

        if (is_in_class) {
            return self.matchFrom(pc + inst_size, pos + 1);
        } else {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
    }

    /// Match character NOT in class (using bit table)
    fn matchCharClassInv(self: *Self, pc: usize, pos: usize, table: *const [32]u8, inst_size: usize) MatchError!MatchResult {
        if (pos >= self.input.len) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
        const c = self.input[pos];

        // Check if character is in the bit table
        const byte_idx = c / 8;
        const bit_idx = @as(u3, @intCast(c % 8));
        const is_in_class = (table[byte_idx] & (@as(u8, 1) << bit_idx)) != 0;

        // Inverted logic: match if NOT in class
        if (!is_in_class) {
            return self.matchFrom(pc + inst_size, pos + 1);
        } else {
            return MatchResult{ .matched = false, .end_pos = pos };
        }
    }

    /// Detect if SPLIT is part of star quantifier pattern
    /// Pattern: SPLIT pc_consume, pc_skip OR SPLIT pc_skip, pc_consume
    /// where pc_consume points to: CHAR; GOTO back_to_split
    fn isStarQuantifier(self: *Self, split_pc: usize, pc1: usize, pc2: usize) MatchError!bool {
        // Try pc1 as the consume path
        if (try self.isStarConsumePath(split_pc, pc1)) return true;

        // Try pc2 as the consume path
        if (try self.isStarConsumePath(split_pc, pc2)) return true;

        return false;
    }

    /// Detect if SPLIT represents a question quantifier (e?)
    /// Question pattern: SPLIT skip, consume; CHAR; (fall-through, no GOTO loop)
    fn isQuestionQuantifier(self: *Self, pc1: usize, pc2: usize) MatchError!bool {
        // Check if pc2 points to a char-consuming instruction
        if (pc2 >= self.bytecode.len) return false;

        const inst = try format.decodeInstruction(self.bytecode, pc2);
        const consumes_char = switch (inst.opcode) {
            .CHAR, .CHAR32, .CHAR_RANGE, .CHAR_RANGE_INV, .CHAR_CLASS, .CHAR2 => true,
            else => false,
        };
        if (!consumes_char) return false;

        // Check that next instruction is NOT a GOTO (which would make it a loop/star)
        const next_pc = pc2 + inst.size;
        if (next_pc >= self.bytecode.len) return true; // Char followed by end

        const next_inst = try format.decodeInstruction(self.bytecode, next_pc);
        if (next_inst.opcode == .GOTO) return false; // It's a loop, not a question

        // pc1 should point near or after the char instruction (the skip path)
        // For greedy ?, pc1 typically points to after the char
        return pc1 >= next_pc or pc1 == next_pc;
    }

    /// Check if a given PC is the consume path of a star quantifier
    fn isStarConsumePath(self: *Self, split_pc: usize, consume_pc: usize) MatchError!bool {
        // Check if consume_pc points to a character-consuming instruction
        if (consume_pc >= self.bytecode.len) return false;

        const inst1 = try format.decodeInstruction(self.bytecode, consume_pc);
        const consumes_char = switch (inst1.opcode) {
            .CHAR, .CHAR32, .CHAR_RANGE, .CHAR_RANGE_INV => true,
            else => false,
        };
        if (!consumes_char) return false;

        // Check if next instruction after char is GOTO
        const next_pc = consume_pc + inst1.size;
        if (next_pc >= self.bytecode.len) return false;

        const inst2 = try format.decodeInstruction(self.bytecode, next_pc);
        if (inst2.opcode != .GOTO) return false;

        // Check if GOTO jumps back to SPLIT (loop pattern)
        const goto_offset = @as(i32, @bitCast(inst2.operands[0]));
        const goto_target: i32 = @intCast(next_pc);
        const target_pc = goto_target + goto_offset;

        return target_pc == @as(i32, @intCast(split_pc));
    }

    /// Match star quantifier with backtracking
    /// pc_char: PC of the character-consuming instruction
    /// pc_rest: PC of the rest of the pattern
    /// greedy: if true, consume maximally first
    fn matchStar(self: *Self, pc_char: usize, pc_rest: usize, pos: usize, greedy: bool) MatchError!MatchResult {
        if (greedy) {
            return self.matchStarGreedy(pc_char, pc_rest, pos);
        } else {
            return self.matchStarLazy(pc_char, pc_rest, pos);
        }
    }

    /// Greedy star: consume maximum, then backtrack
    fn matchStarGreedy(self: *Self, pc_char: usize, pc_rest: usize, pos: usize) MatchError!MatchResult {
        var current_pos = pos;

        // PHASE 1: Greedy consumption - match as many as possible
        var positions = std.ArrayList(usize){};
        defer positions.deinit(self.allocator);

        try positions.append(self.allocator, current_pos);  // Include zero matches

        // Get the character instruction to match
        const char_inst = try format.decodeInstruction(self.bytecode, pc_char);

        while (current_pos < self.input.len) {
            // Match just the character instruction, not the full pattern
            const matched = try self.matchSingleInstruction(char_inst, pc_char, current_pos);
            if (!matched.matched) break;

            // Prevent infinite loop if char didn't consume anything
            if (matched.end_pos == current_pos) break;

            current_pos = matched.end_pos;
            try positions.append(self.allocator, current_pos);
        }

        // PHASE 2: Try rest of pattern from each position (longest first)
        var i: usize = positions.items.len;
        while (i > 0) {
            i -= 1;
            const try_pos = positions.items[i];

            const rest_result = try self.matchFrom(pc_rest, try_pos);
            if (rest_result.matched) {
                return rest_result;
            }
        }

        // Failed to match
        return MatchResult{ .matched = false, .end_pos = pos };
    }

    /// Lazy star: try minimal match first, expand if needed
    fn matchStarLazy(self: *Self, pc_char: usize, pc_rest: usize, pos: usize) MatchError!MatchResult {
        var current_pos = pos;

        // Try matching rest first (zero matches of star)
        const rest_result = try self.matchFrom(pc_rest, current_pos);
        if (rest_result.matched) {
            return rest_result;
        }

        // Get the character instruction to match
        const char_inst = try format.decodeInstruction(self.bytecode, pc_char);

        // If that fails, try consuming one char at a time
        while (current_pos < self.input.len) {
            const matched = try self.matchSingleInstruction(char_inst, pc_char, current_pos);
            if (!matched.matched) break;

            current_pos = matched.end_pos;

            // Try rest again
            const rest_result2 = try self.matchFrom(pc_rest, current_pos);
            if (rest_result2.matched) {
                return rest_result2;
            }

            // Prevent infinite loop
            if (matched.end_pos == current_pos) break;
        }

        return MatchResult{ .matched = false, .end_pos = pos };
    }

    /// Possessive star: consume all without backtracking
    fn matchStarPossessive(self: *Self, pc_char: usize, pc_rest: usize, pos: usize) MatchError!MatchResult {
        var current_pos = pos;

        // Get the character instruction to match
        const char_inst = try format.decodeInstruction(self.bytecode, pc_char);

        // Consume ALL matching characters (possessive = no backtracking)
        while (current_pos < self.input.len) {
            const matched = try self.matchSingleInstruction(char_inst, pc_char, current_pos);
            if (!matched.matched) break;

            // Prevent infinite loop if char didn't consume anything
            if (matched.end_pos == current_pos) break;

            current_pos = matched.end_pos;
        }

        // Try rest ONCE from final position (no backtracking)
        return self.matchFrom(pc_rest, current_pos);
    }

    /// Match a single instruction without advancing PC
    /// Used by star quantifiers to match the repeated element
    fn matchSingleInstruction(self: *Self, inst: Instruction, pc: usize, pos: usize) MatchError!struct { matched: bool, end_pos: usize } {
        switch (inst.opcode) {
            .CHAR32 => {
                // Match specific character
                const expected = @as(u8, @intCast(inst.operands[0]));
                if (pos >= self.input.len) {
                    return .{ .matched = false, .end_pos = pos };
                }
                if (self.input[pos] != expected) {
                    return .{ .matched = false, .end_pos = pos };
                }
                return .{ .matched = true, .end_pos = pos + 1 };
            },

            .CHAR => {
                // Match any character (dot)
                if (pos >= self.input.len) {
                    return .{ .matched = false, .end_pos = pos };
                }
                return .{ .matched = true, .end_pos = pos + 1 };
            },

            .CHAR_RANGE => {
                // Match character in range
                const min = @as(u8, @intCast(inst.operands[0]));
                const max = @as(u8, @intCast(inst.operands[1]));
                if (pos >= self.input.len) {
                    return .{ .matched = false, .end_pos = pos };
                }
                const c = self.input[pos];
                if (c < min or c > max) {
                    return .{ .matched = false, .end_pos = pos };
                }
                return .{ .matched = true, .end_pos = pos + 1 };
            },

            .CHAR_RANGE_INV => {
                // Match character NOT in range
                const min = @as(u8, @intCast(inst.operands[0]));
                const max = @as(u8, @intCast(inst.operands[1]));
                if (pos >= self.input.len) {
                    return .{ .matched = false, .end_pos = pos };
                }
                const c = self.input[pos];
                // Inverted: match if NOT in range
                if (c >= min and c <= max) {
                    return .{ .matched = false, .end_pos = pos };
                }
                return .{ .matched = true, .end_pos = pos + 1 };
            },

            .CHAR_CLASS => {
                // Match character in class (bit table)
                if (pos >= self.input.len) {
                    return .{ .matched = false, .end_pos = pos };
                }
                if (pc + 33 > self.bytecode.len) {
                    return .{ .matched = false, .end_pos = pos };
                }
                const table = self.bytecode[pc + 1 ..][0..32];
                const c = self.input[pos];
                const byte_idx = c / 8;
                const bit_idx = @as(u3, @intCast(c % 8));
                const is_in_class = (table[byte_idx] & (@as(u8, 1) << bit_idx)) != 0;
                if (!is_in_class) {
                    return .{ .matched = false, .end_pos = pos };
                }
                return .{ .matched = true, .end_pos = pos + 1 };
            },

            .CHAR_CLASS_INV => {
                // Match character NOT in class (bit table)
                if (pos >= self.input.len) {
                    return .{ .matched = false, .end_pos = pos };
                }
                if (pc + 33 > self.bytecode.len) {
                    return .{ .matched = false, .end_pos = pos };
                }
                const table = self.bytecode[pc + 1 ..][0..32];
                const c = self.input[pos];
                const byte_idx = c / 8;
                const bit_idx = @as(u3, @intCast(c % 8));
                const is_in_class = (table[byte_idx] & (@as(u8, 1) << bit_idx)) != 0;
                // Inverted: match if NOT in class
                if (is_in_class) {
                    return .{ .matched = false, .end_pos = pos };
                }
                return .{ .matched = true, .end_pos = pos + 1 };
            },

            else => {
                // For other instructions (shouldn't happen in star loop)
                return .{ .matched = false, .end_pos = pos };
            },
        }
    }

    /// Match lookahead assertion (zero-width)
    fn matchLookahead(self: *Self, pc: usize, pos: usize, negative: bool, inst_size: usize) MatchError!MatchResult {
        // Find the end of the lookahead body (LOOKAHEAD_END opcode)
        const lookahead_end_pc = try self.findLookaheadEnd(pc + inst_size);

        // Execute the lookahead pattern starting after the LOOKAHEAD opcode
        // This is a zero-width assertion, so we test at current position
        const result = try self.matchFrom(pc + inst_size, pos);

        if (negative) {
            // Negative lookahead: succeed if pattern did NOT match
            if (!result.matched) {
                // Pattern didn't match, so negative lookahead succeeds
                // Continue after LOOKAHEAD_END without consuming input
                return self.matchFrom(lookahead_end_pc + 1, pos);
            } else {
                // Pattern matched, so negative lookahead fails
                return MatchResult{ .matched = false, .end_pos = pos };
            }
        } else {
            // Positive lookahead: succeed if pattern DID match
            if (result.matched) {
                // Pattern matched, so positive lookahead succeeds
                // Continue after LOOKAHEAD_END without consuming input
                return self.matchFrom(lookahead_end_pc + 1, pos);
            } else {
                // Pattern didn't match, so positive lookahead fails
                return MatchResult{ .matched = false, .end_pos = pos };
            }
        }
    }

    /// Find the position of LOOKAHEAD_END opcode
    fn findLookaheadEnd(self: Self, start_pc: usize) MatchError!usize {
        var pc = start_pc;
        var depth: usize = 1; // Track nested lookaheads

        while (pc < self.bytecode.len) {
            const inst = try format.decodeInstruction(self.bytecode, pc);

            switch (inst.opcode) {
                .LOOKAHEAD, .NEGATIVE_LOOKAHEAD => {
                    // Nested lookahead, increase depth
                    depth += 1;
                    pc += inst.size;
                },
                .LOOKAHEAD_END => {
                    depth -= 1;
                    if (depth == 0) {
                        // Found matching end
                        return pc;
                    }
                    pc += inst.size;
                },
                else => {
                    pc += inst.size;
                },
            }
        }

        // Didn't find matching LOOKAHEAD_END
        return error.UnexpectedEndOfBytecode;
    }

    /// Match lookbehind assertion: (?<=...) or (?<!...)
    /// This matches a pattern BEFORE the current position (zero-width)
    fn matchLookbehind(self: *Self, pc: usize, pos: usize, negative: bool, inst_size: usize) MatchError!MatchResult {
        // Find the end of the lookbehind body
        const lookbehind_end_pc = try self.findLookbehindEnd(pc + inst_size);

        // Try different lookbehind lengths (starting positions)
        // We try from pos backwards up to a reasonable limit
        const max_lookbehind_len = @min(pos, 100); // Limit to 100 chars for performance

        var found_match = false;

        // DEBUG: uncomment to see what's happening
        // std.debug.print("matchLookbehind: pos={}, max_len={}\n", .{pos, max_lookbehind_len});

        // Try different starting positions, from closest to farthest
        var try_len: usize = 1;
        while (try_len <= max_lookbehind_len) : (try_len += 1) {
            const start_pos = pos - try_len;

            // Try to match the pattern from start_pos
            const result = try self.matchFrom(pc + inst_size, start_pos);

            // DEBUG: uncomment to see results
            // std.debug.print("  try_len={}, start_pos={}, matched={}, end_pos={}\n", .{try_len, start_pos, result.matched, result.end_pos});

            // Check if match ends exactly at current position (pos)
            if (result.matched and result.end_pos == pos) {
                found_match = true;
                break;
            }
        }

        // Also try empty match (zero-length lookbehind)
        if (!found_match) {
            const result = try self.matchFrom(pc + inst_size, pos);
            // DEBUG
            // std.debug.print("  empty match: matched={}, end_pos={}\n", .{result.matched, result.end_pos});
            if (result.matched and result.end_pos == pos) {
                found_match = true;
            }
        }

        if (negative) {
            // Negative lookbehind: succeed if pattern did NOT match
            if (!found_match) {
                // Pattern didn't match, so negative lookbehind succeeds
                // Continue after LOOKBEHIND_END without consuming input
                return self.matchFrom(lookbehind_end_pc + 1, pos);
            } else {
                // Pattern matched, so negative lookbehind fails
                return MatchResult{ .matched = false, .end_pos = pos };
            }
        } else {
            // Positive lookbehind: succeed if pattern DID match
            if (found_match) {
                // Pattern matched, so positive lookbehind succeeds
                // Continue after LOOKBEHIND_END without consuming input
                return self.matchFrom(lookbehind_end_pc + 1, pos);
            } else {
                // Pattern didn't match, so positive lookbehind fails
                return MatchResult{ .matched = false, .end_pos = pos };
            }
        }
    }

    /// Find the position of LOOKBEHIND_END opcode
    fn findLookbehindEnd(self: Self, start_pc: usize) MatchError!usize {
        var pc = start_pc;
        var depth: usize = 1; // Track nested lookbehinds

        while (pc < self.bytecode.len) {
            const inst = try format.decodeInstruction(self.bytecode, pc);

            switch (inst.opcode) {
                .LOOKBEHIND, .NEGATIVE_LOOKBEHIND => {
                    // Nested lookbehind, increase depth
                    depth += 1;
                    pc += inst.size;
                },
                .LOOKBEHIND_END => {
                    depth -= 1;
                    if (depth == 0) {
                        // Found matching end
                        return pc;
                    }
                    pc += inst.size;
                },
                else => {
                    pc += inst.size;
                },
            }
        }

        // Didn't find matching LOOKBEHIND_END
        return error.UnexpectedEndOfBytecode;
    }

    /// Match backreference to capture group
    fn matchBackRef(self: *Self, pc: usize, pos: usize, group: usize, case_insensitive: bool, inst_size: usize) MatchError!MatchResult {
        // Check if group index is valid
        if (group >= MAX_CAPTURE_GROUPS) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }

        // Get the captured text
        const capture = self.captures[group];
        if (!capture.isValid()) {
            // Reference to uncaptured group fails
            return MatchResult{ .matched = false, .end_pos = pos };
        }

        const cap_start = capture.start.?;
        const cap_end = capture.end.?;
        const cap_len = cap_end - cap_start;

        // Check if we have enough input left
        if (pos + cap_len > self.input.len) {
            return MatchResult{ .matched = false, .end_pos = pos };
        }

        // Compare captured text with current position
        const captured_text = self.input[cap_start..cap_end];
        const current_text = self.input[pos .. pos + cap_len];

        // Match character by character
        for (captured_text, 0..) |cap_char, i| {
            const cur_char = current_text[i];

            if (case_insensitive) {
                // Case-insensitive comparison
                if (std.ascii.toLower(cap_char) != std.ascii.toLower(cur_char)) {
                    return MatchResult{ .matched = false, .end_pos = pos };
                }
            } else {
                // Case-sensitive comparison
                if (cap_char != cur_char) {
                    return MatchResult{ .matched = false, .end_pos = pos };
                }
            }
        }

        // Success: advance past the matched backreference
        return self.matchFrom(pc + inst_size, pos + cap_len);
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

test "RecursiveMatcher: question quantifier" {
    const compiler = @import("../codegen/compiler.zig");

    const result = try compiler.compileSimple(std.testing.allocator, "a?");
    defer result.deinit();

    // Test with empty string (should match)
    {
        var matcher = RecursiveMatcher.init(std.testing.allocator, result.bytecode, "");
        const exec_result = try matcher.matchFrom(0, 0);
        try std.testing.expect(exec_result.matched);
        try std.testing.expectEqual(@as(usize, 0), exec_result.end_pos);
    }

    // Test with "a" (should match and consume)
    {
        var matcher = RecursiveMatcher.init(std.testing.allocator, result.bytecode, "a");
        const exec_result = try matcher.matchFrom(0, 0);
        try std.testing.expect(exec_result.matched);
        try std.testing.expectEqual(@as(usize, 1), exec_result.end_pos);
    }
}

test "RecursiveMatcher: simple star quantifier" {
    const compiler = @import("../codegen/compiler.zig");

    const result = try compiler.compileSimple(std.testing.allocator, "a*");
    defer result.deinit();

    // Test with empty string (should match)
    {
        var matcher = RecursiveMatcher.init(std.testing.allocator, result.bytecode, "");
        const exec_result = try matcher.matchFrom(0, 0);
        try std.testing.expect(exec_result.matched);
        try std.testing.expectEqual(@as(usize, 0), exec_result.end_pos);
    }

    // Test with "aaa" (should match)
    {
        var matcher = RecursiveMatcher.init(std.testing.allocator, result.bytecode, "aaa");
        const exec_result = try matcher.matchFrom(0, 0);

        try std.testing.expect(exec_result.matched);
        try std.testing.expectEqual(@as(usize, 3), exec_result.end_pos);
    }
}

test "RecursiveMatcher: ReDoS protection - step limit" {
    const compiler = @import("../codegen/compiler.zig");

    // Patrón que causa backtracking exponencial: (a+)+b
    const result = try compiler.compileSimple(std.testing.allocator, "(a+)+b");
    defer result.deinit();

    // Input malicioso: muchas 'a's sin 'b' al final
    const malicious_input = "aaaaaaaaaaaaaaaaaaaaX"; // 20 'a's + 'X'

    var matcher = RecursiveMatcher.init(std.testing.allocator, result.bytecode, malicious_input);

    // Debería alcanzar el límite de pasos y lanzar error
    const exec_result = matcher.matchFrom(0, 0);
    try std.testing.expectError(error.StepLimitExceeded, exec_result);
}

test "RecursiveMatcher: ReDoS protection - recursion limit" {
    const compiler = @import("../codegen/compiler.zig");

    const result = try compiler.compileSimple(std.testing.allocator, "a+");
    defer result.deinit();

    // Crear matcher con límites muy bajos
    const options = ExecOptions.withLimits(5, 50);
    var matcher = RecursiveMatcher.initWithOptions(
        std.testing.allocator,
        result.bytecode,
        "aaaaaaaaaa", // 10 'a's
        options,
    );

    // Debería alcanzar el límite de recursión
    const exec_result = matcher.matchFrom(0, 0);
    try std.testing.expectError(error.RecursionLimitExceeded, exec_result);
}

test "RecursiveMatcher: ExecOptions - default values" {
    const options = ExecOptions{};
    try std.testing.expectEqual(@as(usize, DEFAULT_MAX_RECURSION_DEPTH), options.max_recursion_depth);
    try std.testing.expectEqual(@as(usize, DEFAULT_MAX_STEPS), options.max_steps);
}

test "RecursiveMatcher: ExecOptions - unlimited" {
    const options = ExecOptions.unlimited();
    try std.testing.expectEqual(@as(usize, 0), options.max_recursion_depth);
    try std.testing.expectEqual(@as(usize, 0), options.max_steps);
}

test "RecursiveMatcher: ExecOptions - custom limits" {
    const options = ExecOptions.withLimits(100, 5000);
    try std.testing.expectEqual(@as(usize, 100), options.max_recursion_depth);
    try std.testing.expectEqual(@as(usize, 5000), options.max_steps);
}
