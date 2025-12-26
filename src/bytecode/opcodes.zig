//! Bytecode opcodes for zregexp
//!
//! This module defines all opcodes used in the regex bytecode virtual machine.
//! Based on QuickJS libregexp with 33 opcodes organized by category.
//!
//! Bytecode format:
//! - Each instruction starts with an 8-bit opcode
//! - Followed by operands (size depends on opcode)
//! - All multi-byte values are little-endian

const std = @import("std");

/// Bytecode opcode enumeration
/// Matches libregexp opcode values for compatibility
pub const Opcode = enum(u8) {
    // =========================================================================
    // Character Matching (0x00-0x0F)
    // =========================================================================

    /// Match any character except newline (unless /s flag)
    /// Format: [CHAR]
    CHAR = 0x00,

    /// Match specific character
    /// Format: [CHAR c:u32]
    CHAR32 = 0x01,

    /// Match one of two characters (optimization)
    /// Format: [CHAR2 c1:u32 c2:u32]
    CHAR2 = 0x02,

    /// Match character in range [min, max]
    /// Format: [CHAR_RANGE min:u32 max:u32]
    CHAR_RANGE = 0x03,

    /// Match character in inverted range (not in [min, max])
    /// Format: [CHAR_RANGE_INV min:u32 max:u32]
    CHAR_RANGE_INV = 0x04,

    /// Match character class (with inline bit table)
    /// Format: [CHAR_CLASS table:32bytes]
    CHAR_CLASS = 0x05,

    /// Match inverted character class (with inline bit table)
    /// Format: [CHAR_CLASS_INV table:32bytes]
    CHAR_CLASS_INV = 0x06,

    // =========================================================================
    // Control Flow (0x10-0x1F)
    // =========================================================================

    /// Match succeeds
    /// Format: [MATCH]
    MATCH = 0x10,

    /// Unconditional jump
    /// Format: [GOTO offset:i32]
    GOTO = 0x11,

    /// Split execution (for alternation, quantifiers)
    /// Format: [SPLIT offset1:i32 offset2:i32]
    /// Try offset1 first, backtrack to offset2 on failure
    SPLIT = 0x12,

    /// Split with greedy preference
    /// Format: [SPLIT_GREEDY offset1:i32 offset2:i32]
    SPLIT_GREEDY = 0x13,

    /// Split with lazy preference
    /// Format: [SPLIT_LAZY offset1:i32 offset2:i32]
    SPLIT_LAZY = 0x14,

    /// Split with possessive/atomic behavior (no backtracking)
    /// Format: [SPLIT_POSSESSIVE offset1:i32 offset2:i32]
    SPLIT_POSSESSIVE = 0x15,

    /// Loop check (for quantifiers)
    /// Format: [LOOP counter_index:u8 max:u32 offset:i32]
    LOOP = 0x16,

    // =========================================================================
    // Capture Groups (0x20-0x2F)
    // =========================================================================

    /// Save capture group start position
    /// Format: [SAVE_START group:u8]
    SAVE_START = 0x20,

    /// Save capture group end position
    /// Format: [SAVE_END group:u8]
    SAVE_END = 0x21,

    /// Save named capture group start
    /// Format: [SAVE_START_NAMED group:u8 name_offset:u32]
    SAVE_START_NAMED = 0x22,

    /// Save named capture group end
    /// Format: [SAVE_END_NAMED group:u8 name_offset:u32]
    SAVE_END_NAMED = 0x23,

    // =========================================================================
    // Backreferences (0x30-0x3F)
    // =========================================================================

    /// Match backreference to capture group
    /// Format: [BACK_REF group:u8]
    BACK_REF = 0x30,

    /// Match backreference (case insensitive)
    /// Format: [BACK_REF_I group:u8]
    BACK_REF_I = 0x31,

    // =========================================================================
    // Assertions (0x40-0x4F)
    // =========================================================================

    /// Assert start of line (^ or \A)
    /// Format: [LINE_START]
    LINE_START = 0x40,

    /// Assert end of line ($ or \Z)
    /// Format: [LINE_END]
    LINE_END = 0x41,

    /// Assert word boundary (\b)
    /// Format: [WORD_BOUNDARY]
    WORD_BOUNDARY = 0x42,

    /// Assert non-word boundary (\B)
    /// Format: [NOT_WORD_BOUNDARY]
    NOT_WORD_BOUNDARY = 0x43,

    /// Assert start of string (\A)
    /// Format: [STRING_START]
    STRING_START = 0x44,

    /// Assert end of string (\z)
    /// Format: [STRING_END]
    STRING_END = 0x45,

    // =========================================================================
    // Lookaround (0x50-0x5F)
    // =========================================================================

    /// Positive lookahead
    /// Format: [LOOKAHEAD len:u32 ... LOOKAHEAD_END]
    LOOKAHEAD = 0x50,

    /// Negative lookahead
    /// Format: [NEGATIVE_LOOKAHEAD len:u32 ... LOOKAHEAD_END]
    NEGATIVE_LOOKAHEAD = 0x51,

    /// Positive lookbehind
    /// Format: [LOOKBEHIND len:u32 ... LOOKBEHIND_END]
    LOOKBEHIND = 0x52,

    /// Negative lookbehind
    /// Format: [NEGATIVE_LOOKBEHIND len:u32 ... LOOKBEHIND_END]
    NEGATIVE_LOOKBEHIND = 0x53,

    /// End of lookahead assertion
    /// Format: [LOOKAHEAD_END]
    LOOKAHEAD_END = 0x54,

    /// End of lookbehind assertion
    /// Format: [LOOKBEHIND_END]
    LOOKBEHIND_END = 0x55,

    // =========================================================================
    // Special (0x60-0x6F)
    // =========================================================================

    /// Push current position to stack
    /// Format: [PUSH_POS]
    PUSH_POS = 0x60,

    /// Pop and check position hasn't changed
    /// Format: [CHECK_POS]
    CHECK_POS = 0x61,

    _,

    /// Get the category of this opcode
    pub fn category(self: Opcode) OpcodeCategory {
        return switch (self) {
            .CHAR, .CHAR32, .CHAR2, .CHAR_RANGE, .CHAR_RANGE_INV, .CHAR_CLASS, .CHAR_CLASS_INV => .character_match,
            .MATCH, .GOTO, .SPLIT, .SPLIT_GREEDY, .SPLIT_LAZY, .SPLIT_POSSESSIVE, .LOOP => .control_flow,
            .SAVE_START, .SAVE_END, .SAVE_START_NAMED, .SAVE_END_NAMED => .capture,
            .BACK_REF, .BACK_REF_I => .backreference,
            .LINE_START, .LINE_END, .WORD_BOUNDARY, .NOT_WORD_BOUNDARY, .STRING_START, .STRING_END => .assertion,
            .LOOKAHEAD, .NEGATIVE_LOOKAHEAD, .LOOKBEHIND, .NEGATIVE_LOOKBEHIND, .LOOKAHEAD_END, .LOOKBEHIND_END => .lookaround,
            .PUSH_POS, .CHECK_POS => .special,
            _ => .unknown,
        };
    }

    /// Get the size of this instruction in bytes (including opcode)
    pub fn size(self: Opcode) u8 {
        return switch (self) {
            // 1 byte (opcode only)
            .CHAR, .MATCH, .LINE_START, .LINE_END, .WORD_BOUNDARY, .NOT_WORD_BOUNDARY,
            .STRING_START, .STRING_END, .LOOKAHEAD_END, .LOOKBEHIND_END,
            .PUSH_POS, .CHECK_POS => 1,

            // 2 bytes (opcode + u8)
            .SAVE_START, .SAVE_END, .BACK_REF, .BACK_REF_I => 2,

            // 5 bytes (opcode + u32)
            .CHAR32, .LOOKAHEAD, .NEGATIVE_LOOKAHEAD, .LOOKBEHIND, .NEGATIVE_LOOKBEHIND => 5,

            // 6 bytes (opcode + u8 + u32)
            .SAVE_START_NAMED, .SAVE_END_NAMED => 6,

            // 5 bytes (opcode + i32)
            .GOTO => 5,

            // 9 bytes (opcode + 2 * u32)
            .CHAR2, .CHAR_RANGE, .CHAR_RANGE_INV => 9,

            // 10 bytes (opcode + u8 + u32 + i32)
            .LOOP => 10,

            // 9 bytes (opcode + 2 * i32 for offsets)
            .SPLIT, .SPLIT_GREEDY, .SPLIT_LAZY, .SPLIT_POSSESSIVE => 9,

            // 33 bytes (opcode + 32 bytes bit table)
            .CHAR_CLASS, .CHAR_CLASS_INV => 33,

            _ => 1, // Unknown opcodes default to 1 byte
        };
    }

    /// Check if this opcode terminates execution
    pub fn isTerminal(self: Opcode) bool {
        return self == .MATCH;
    }

    /// Check if this opcode is a control flow instruction
    pub fn isControlFlow(self: Opcode) bool {
        return self.category() == .control_flow;
    }

    /// Check if this opcode can cause backtracking
    pub fn canBacktrack(self: Opcode) bool {
        return switch (self) {
            .SPLIT, .SPLIT_GREEDY, .SPLIT_LAZY, .LOOP => true,
            else => false,
        };
    }

    /// Get human-readable name
    pub fn name(self: Opcode) []const u8 {
        return @tagName(self);
    }
};

/// Opcode category for classification
pub const OpcodeCategory = enum {
    character_match,
    control_flow,
    capture,
    backreference,
    assertion,
    lookaround,
    special,
    unknown,
};

/// Metadata about an opcode
pub const OpcodeInfo = struct {
    opcode: Opcode,
    mnemonic: []const u8,
    description: []const u8,
    operands: []const OperandType,
    category: OpcodeCategory,

    pub const OperandType = enum {
        u8_value,
        u16_value,
        u32_value,
        i32_offset,
        group_index,
        name_offset,
        counter_index,
    };
};

/// Get metadata for an opcode
pub fn getOpcodeInfo(opcode: Opcode) OpcodeInfo {
    return switch (opcode) {
        .CHAR => .{
            .opcode = opcode,
            .mnemonic = "CHAR",
            .description = "Match any character except newline",
            .operands = &[_]OpcodeInfo.OperandType{},
            .category = .character_match,
        },
        .CHAR32 => .{
            .opcode = opcode,
            .mnemonic = "CHAR32",
            .description = "Match specific character",
            .operands = &[_]OpcodeInfo.OperandType{.u32_value},
            .category = .character_match,
        },
        .MATCH => .{
            .opcode = opcode,
            .mnemonic = "MATCH",
            .description = "Match succeeds",
            .operands = &[_]OpcodeInfo.OperandType{},
            .category = .control_flow,
        },
        .SPLIT => .{
            .opcode = opcode,
            .mnemonic = "SPLIT",
            .description = "Split execution for alternation",
            .operands = &[_]OpcodeInfo.OperandType{ .i32_offset, .i32_offset },
            .category = .control_flow,
        },
        .SAVE_START => .{
            .opcode = opcode,
            .mnemonic = "SAVE_START",
            .description = "Save capture group start position",
            .operands = &[_]OpcodeInfo.OperandType{.group_index},
            .category = .capture,
        },
        // Add more as needed...
        else => .{
            .opcode = opcode,
            .mnemonic = opcode.name(),
            .description = "No description available",
            .operands = &[_]OpcodeInfo.OperandType{},
            .category = opcode.category(),
        },
    };
}

// =============================================================================
// Tests
// =============================================================================

test "Opcode: values match expected" {
    try std.testing.expectEqual(@as(u8, 0x00), @intFromEnum(Opcode.CHAR));
    try std.testing.expectEqual(@as(u8, 0x10), @intFromEnum(Opcode.MATCH));
    try std.testing.expectEqual(@as(u8, 0x20), @intFromEnum(Opcode.SAVE_START));
    try std.testing.expectEqual(@as(u8, 0x30), @intFromEnum(Opcode.BACK_REF));
    try std.testing.expectEqual(@as(u8, 0x40), @intFromEnum(Opcode.LINE_START));
    try std.testing.expectEqual(@as(u8, 0x50), @intFromEnum(Opcode.LOOKAHEAD));
}

test "Opcode: category classification" {
    try std.testing.expectEqual(OpcodeCategory.character_match, Opcode.CHAR.category());
    try std.testing.expectEqual(OpcodeCategory.control_flow, Opcode.MATCH.category());
    try std.testing.expectEqual(OpcodeCategory.capture, Opcode.SAVE_START.category());
    try std.testing.expectEqual(OpcodeCategory.backreference, Opcode.BACK_REF.category());
    try std.testing.expectEqual(OpcodeCategory.assertion, Opcode.LINE_START.category());
    try std.testing.expectEqual(OpcodeCategory.lookaround, Opcode.LOOKAHEAD.category());
}

test "Opcode: size calculations" {
    try std.testing.expectEqual(@as(u8, 1), Opcode.CHAR.size());
    try std.testing.expectEqual(@as(u8, 1), Opcode.MATCH.size());
    try std.testing.expectEqual(@as(u8, 2), Opcode.SAVE_START.size());
    try std.testing.expectEqual(@as(u8, 5), Opcode.CHAR32.size());
    try std.testing.expectEqual(@as(u8, 9), Opcode.SPLIT.size());
}

test "Opcode: terminal check" {
    try std.testing.expect(Opcode.MATCH.isTerminal());
    try std.testing.expect(!Opcode.CHAR.isTerminal());
    try std.testing.expect(!Opcode.SPLIT.isTerminal());
}

test "Opcode: control flow check" {
    try std.testing.expect(Opcode.MATCH.isControlFlow());
    try std.testing.expect(Opcode.GOTO.isControlFlow());
    try std.testing.expect(Opcode.SPLIT.isControlFlow());
    try std.testing.expect(!Opcode.CHAR.isControlFlow());
    try std.testing.expect(!Opcode.SAVE_START.isControlFlow());
}

test "Opcode: backtracking check" {
    try std.testing.expect(Opcode.SPLIT.canBacktrack());
    try std.testing.expect(Opcode.LOOP.canBacktrack());
    try std.testing.expect(!Opcode.MATCH.canBacktrack());
    try std.testing.expect(!Opcode.CHAR.canBacktrack());
}

test "Opcode: name retrieval" {
    try std.testing.expectEqualStrings("CHAR", Opcode.CHAR.name());
    try std.testing.expectEqualStrings("MATCH", Opcode.MATCH.name());
    try std.testing.expectEqualStrings("SPLIT", Opcode.SPLIT.name());
}

test "OpcodeInfo: basic retrieval" {
    const info = getOpcodeInfo(.CHAR32);
    try std.testing.expectEqual(Opcode.CHAR32, info.opcode);
    try std.testing.expectEqualStrings("CHAR32", info.mnemonic);
    try std.testing.expectEqual(@as(usize, 1), info.operands.len);
}

test "OpcodeCategory: all categories represented" {
    const categories = [_]OpcodeCategory{
        .character_match,
        .control_flow,
        .capture,
        .backreference,
        .assertion,
        .lookaround,
        .special,
        .unknown,
    };
    _ = categories;
}
