//! Code generator - Translates AST to bytecode
//!
//! This module implements the code generation phase of the compiler,
//! converting the Abstract Syntax Tree into executable bytecode.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("../parser/ast.zig");
const bytecode = @import("../bytecode/writer.zig");
const opcodes = @import("../bytecode/opcodes.zig");
const compiler = @import("compiler.zig");

const Node = ast.Node;
const NodeType = ast.NodeType;
const BytecodeWriter = bytecode.BytecodeWriter;
const Label = bytecode.Label;
const Opcode = opcodes.Opcode;
const CompileOptions = compiler.CompileOptions;

/// Code generation error
pub const CodegenError = error{
    UnsupportedNode,
    InvalidPattern,
    TooManyGroups,
    OutOfMemory,
    // BytecodeWriter errors
    BufferTooSmall,
    UnknownOpcode,
};

/// Code generator for translating AST to bytecode
pub const CodeGenerator = struct {
    allocator: Allocator,
    writer: *BytecodeWriter,
    group_count: u8,
    options: CompileOptions,

    const Self = @This();

    /// Maximum ASCII character value
    const MAX_ASCII = 127;

    /// Difference between uppercase and lowercase ASCII letters
    const CASE_DIFF = 32;

    /// Initialize a new code generator
    pub fn init(allocator: Allocator, writer: *BytecodeWriter, options: CompileOptions) Self {
        return .{
            .allocator = allocator,
            .writer = writer,
            .group_count = 0,
            .options = options,
        };
    }

    /// Generate bytecode from an AST
    pub fn generate(self: *Self, root: *Node) CodegenError!void {
        try self.generateNode(root);
        // Emit MATCH at the end to signal successful match
        try self.writer.emitSimple(.MATCH);
    }

    /// Generate code for a node
    fn generateNode(self: *Self, node: *Node) CodegenError!void {
        switch (node.type) {
            .char => try self.generateChar(node),
            .char_range => try self.generateCharRange(node),
            .char_class => try self.generateCharClass(node),
            .dot => try self.generateDot(),
            .star => try self.generateStar(node),
            .plus => try self.generatePlus(node),
            .question => try self.generateQuestion(node),
            .repeat => try self.generateRepeat(node),
            .lazy_star => try self.generateLazyStar(node),
            .lazy_plus => try self.generateLazyPlus(node),
            .lazy_question => try self.generateLazyQuestion(node),
            .lazy_repeat => try self.generateLazyRepeat(node),
            .possessive_star => try self.generatePossessiveStar(node),
            .possessive_plus => try self.generatePossessivePlus(node),
            .possessive_question => try self.generatePossessiveQuestion(node),
            .sequence => try self.generateSequence(node),
            .alternation => try self.generateAlternation(node),
            .group => try self.generateGroup(node),
            .non_capturing_group => try self.generateNonCapturingGroup(node),
            .back_ref => try self.generateBackRef(node),
            .lookahead => try self.generateLookahead(node, false),
            .negative_lookahead => try self.generateLookahead(node, true),
            .lookbehind => try self.generateLookbehind(node, false),
            .negative_lookbehind => try self.generateLookbehind(node, true),
            .anchor_start => try self.generateAnchorStart(),
            .anchor_end => try self.generateAnchorEnd(),
            .word_boundary => try self.generateWordBoundary(),
            .not_word_boundary => try self.generateNotWordBoundary(),
        }
    }

    // =========================================================================
    // Character Matching
    // =========================================================================

    /// Generate code for a character literal
    fn generateChar(self: *Self, node: *Node) !void {
        const char = node.char_value;

        // If case-insensitive mode and this is an ASCII letter, generate alternation
        if (self.options.case_insensitive and char <= MAX_ASCII) {
            const c = @as(u8, @intCast(char));

            // Check if it's a letter
            const is_lower = c >= 'a' and c <= 'z';
            const is_upper = c >= 'A' and c <= 'Z';

            if (is_lower or is_upper) {
                // Generate alternation: lowercase|uppercase
                const lower = if (is_lower) c else c + CASE_DIFF;
                const upper = if (is_upper) c else c - CASE_DIFF;

                // Generate alternation: SPLIT upper_label, lower_label;
                // lower_label: lower; GOTO after; upper_label: upper; after:
                var lower_label = try self.writer.createLabel();
                var upper_label = try self.writer.createLabel();
                var after_label = try self.writer.createLabel();

                try self.writer.emitSplit(.SPLIT, upper_label, lower_label);
                try self.writer.defineLabel(&lower_label);
                try self.writer.emit1(.CHAR32, lower);
                try self.writer.emitJump(.GOTO, after_label);
                try self.writer.defineLabel(&upper_label);
                try self.writer.emit1(.CHAR32, upper);
                try self.writer.defineLabel(&after_label);

                return;
            }
        }

        // Normal case: just emit the character
        try self.writer.emit1(.CHAR32, char);
    }

    /// Generate code for a character range [a-z]
    fn generateCharRange(self: *Self, node: *Node) !void {
        const opcode: opcodes.Opcode = if (node.inverted) .CHAR_RANGE_INV else .CHAR_RANGE;
        try self.writer.emit2(opcode, node.range_start, node.range_end);
    }

    /// Generate code for a character class [abc] or [a-z0-9]
    fn generateCharClass(self: *Self, node: *Node) !void {
        const BitTable = @import("../utils/bittable.zig").BitTable;

        if (node.children.items.len == 0) {
            return error.InvalidPattern;
        }

        if (node.children.items.len == 1 and !node.inverted) {
            // Single item, not inverted: just generate the child directly
            const child = node.children.items[0];
            try self.generateNode(child);
            return;
        }

        // For inverted single items or multiple items: use bit table
        var table = BitTable.init();

        // Build bit table from children
        for (node.children.items) |child| {
            switch (child.type) {
                .char => {
                    const c = @as(u8, @intCast(child.char_value));
                    table.set(c);
                },
                .char_range => {
                    const start = @as(u8, @intCast(child.range_start));
                    const end = @as(u8, @intCast(child.range_end));
                    table.addRange(start, end);
                },
                else => {
                    // Unsupported child type in character class
                    return error.InvalidPattern;
                },
            }
        }

        // Emit CHAR_CLASS or CHAR_CLASS_INV with inline bit table
        const opcode: opcodes.Opcode = if (node.inverted) .CHAR_CLASS_INV else .CHAR_CLASS;
        try self.writer.emitCharClass(opcode, &table.bits);
    }

    /// Generate code for dot (any character)
    fn generateDot(self: *Self) !void {
        try self.writer.emitSimple(.CHAR);
    }

    // =========================================================================
    // Quantifiers
    // =========================================================================

    /// Generate code for star quantifier: e*
    /// Pattern: L1: SPLIT L2, L3; e; GOTO L1; L2: ...
    fn generateStar(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        var loop_label = try self.writer.createLabel();
        var end_label = try self.writer.createLabel();

        try self.writer.defineLabel(&loop_label);
        try self.writer.emitSplit(.SPLIT, end_label, loop_label); // Non-greedy for now

        try self.generateNode(node.children.items[0]);
        try self.writer.emitJump(.GOTO, loop_label);

        try self.writer.defineLabel(&end_label);
    }

    /// Generate code for plus quantifier: e+
    /// Pattern: L1: e; SPLIT L1, L2; L2: ...
    fn generatePlus(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        var loop_label = try self.writer.createLabel();
        var end_label = try self.writer.createLabel();

        try self.writer.defineLabel(&loop_label);
        try self.generateNode(node.children.items[0]);
        try self.writer.emitSplit(.SPLIT_GREEDY, loop_label, end_label); // Greedy

        try self.writer.defineLabel(&end_label);
    }

    /// Generate code for question quantifier: e?
    /// Pattern: SPLIT skip, consume; consume: e; skip: ...
    /// For greedy behavior, VM tries both paths and prefers longer match
    fn generateQuestion(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        var skip_label = try self.writer.createLabel();
        var consume_label = try self.writer.createLabel();

        // SPLIT: first path = skip (don't consume), second path = consume
        try self.writer.emitSplit(.SPLIT, skip_label, consume_label);

        // Define consume label immediately (fall-through)
        try self.writer.defineLabel(&consume_label);
        try self.generateNode(node.children.items[0]);

        // Define skip label (after the character)
        try self.writer.defineLabel(&skip_label);
    }

    /// Generate code for repeat quantifier: e{n,m}
    fn generateRepeat(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        const min = node.repeat_min;
        const max = node.repeat_max;

        // Generate min required repetitions
        for (0..min) |_| {
            try self.generateNode(node.children.items[0]);
        }

        // Check if unbounded {n,}
        const is_unbounded = max == std.math.maxInt(u32);

        if (is_unbounded) {
            // Pattern: {n,} = n required + e* (zero or more)
            // Generate e*: L1: SPLIT L2, L1; e; GOTO L1; L2: ...
            var loop_label = try self.writer.createLabel();
            var end_label = try self.writer.createLabel();

            try self.writer.defineLabel(&loop_label);
            try self.writer.emitSplit(.SPLIT_GREEDY, loop_label, end_label);
            try self.generateNode(node.children.items[0]);
            try self.writer.emitJump(.GOTO, loop_label);
            try self.writer.defineLabel(&end_label);
        } else if (max > min) {
            // Generate optional repetitions up to max
            // Pattern for each optional: SPLIT skip, consume; consume: e; skip: ...
            const optional_count = max - min;
            for (0..optional_count) |_| {
                var skip_label = try self.writer.createLabel();
                var consume_label = try self.writer.createLabel();

                // Greedy: try to consume first (longer match preferred)
                try self.writer.emitSplit(.SPLIT_GREEDY, consume_label, skip_label);
                try self.writer.defineLabel(&consume_label);
                try self.generateNode(node.children.items[0]);
                try self.writer.defineLabel(&skip_label);
            }
        }
    }

    /// Generate code for lazy star quantifier: e*?
    /// Pattern: L1: SPLIT_LAZY L2, L3; e; GOTO L1; L2: ...
    /// Lazy = try empty first, then try consuming
    fn generateLazyStar(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        var loop_label = try self.writer.createLabel();
        var end_label = try self.writer.createLabel();

        try self.writer.defineLabel(&loop_label);
        try self.writer.emitSplit(.SPLIT_LAZY, end_label, loop_label);

        try self.generateNode(node.children.items[0]);
        try self.writer.emitJump(.GOTO, loop_label);

        try self.writer.defineLabel(&end_label);
    }

    /// Generate code for lazy plus quantifier: e+?
    /// Pattern: L1: e; SPLIT_LAZY L2, L1; L2: ...
    /// Lazy = match once, then try exit before consuming more
    fn generateLazyPlus(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        var loop_label = try self.writer.createLabel();
        var end_label = try self.writer.createLabel();

        try self.writer.defineLabel(&loop_label);
        try self.generateNode(node.children.items[0]);
        try self.writer.emitSplit(.SPLIT_LAZY, end_label, loop_label);

        try self.writer.defineLabel(&end_label);
    }

    /// Generate code for lazy question quantifier: e??
    /// Pattern: SPLIT_LAZY skip, consume; consume: e; skip: ...
    /// Lazy = try skip first, then try consuming
    fn generateLazyQuestion(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        var skip_label = try self.writer.createLabel();
        var consume_label = try self.writer.createLabel();

        // SPLIT_LAZY: first path = skip (don't consume), second path = consume
        // For lazy, we prefer skip (minimal match)
        try self.writer.emitSplit(.SPLIT_LAZY, skip_label, consume_label);

        // Define consume label immediately (fall-through)
        try self.writer.defineLabel(&consume_label);
        try self.generateNode(node.children.items[0]);

        // Define skip label (after the character)
        try self.writer.defineLabel(&skip_label);
    }

    /// Generate code for lazy repeat quantifier: e{n,m}?
    /// Same as repeat but uses SPLIT_LAZY for minimal matching
    fn generateLazyRepeat(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        const min = node.repeat_min;
        const max = node.repeat_max;

        // Generate min required repetitions
        for (0..min) |_| {
            try self.generateNode(node.children.items[0]);
        }

        // Check if unbounded {n,}?
        const is_unbounded = max == std.math.maxInt(u32);

        if (is_unbounded) {
            // Pattern: {n,}? = n required + e*? (lazy zero or more)
            // Generate e*?: L1: SPLIT_LAZY L2, L1; e; GOTO L1; L2: ...
            var loop_label = try self.writer.createLabel();
            var end_label = try self.writer.createLabel();

            try self.writer.defineLabel(&loop_label);
            try self.writer.emitSplit(.SPLIT_LAZY, end_label, loop_label);
            try self.generateNode(node.children.items[0]);
            try self.writer.emitJump(.GOTO, loop_label);
            try self.writer.defineLabel(&end_label);
        } else if (max > min) {
            // Generate optional repetitions up to max
            // Pattern for each optional: SPLIT_LAZY skip, consume; consume: e; skip: ...
            const optional_count = max - min;
            for (0..optional_count) |_| {
                var skip_label = try self.writer.createLabel();
                var consume_label = try self.writer.createLabel();

                // Lazy: try to skip first (minimal match preferred)
                try self.writer.emitSplit(.SPLIT_LAZY, skip_label, consume_label);
                try self.writer.defineLabel(&consume_label);
                try self.generateNode(node.children.items[0]);
                try self.writer.defineLabel(&skip_label);
            }
        }
    }

    /// Generate code for possessive star quantifier: e*+
    /// Pattern: L1: SPLIT_POSSESSIVE L2, L3; e; GOTO L1; L2: ...
    /// Possessive = consume all without backtracking
    fn generatePossessiveStar(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        var loop_label = try self.writer.createLabel();
        var end_label = try self.writer.createLabel();

        try self.writer.defineLabel(&loop_label);
        try self.writer.emitSplit(.SPLIT_POSSESSIVE, end_label, loop_label);

        try self.generateNode(node.children.items[0]);
        try self.writer.emitJump(.GOTO, loop_label);

        try self.writer.defineLabel(&end_label);
    }

    /// Generate code for possessive plus quantifier: e++
    /// Pattern: e; L1: SPLIT_POSSESSIVE L2, L1; e; GOTO L1; L2: ...
    /// Possessive = match at least once, then consume all without backtracking
    fn generatePossessivePlus(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        var loop_label = try self.writer.createLabel();
        var end_label = try self.writer.createLabel();

        // Match at least once
        try self.generateNode(node.children.items[0]);

        // Loop for more (possessive)
        try self.writer.defineLabel(&loop_label);
        try self.writer.emitSplit(.SPLIT_POSSESSIVE, end_label, loop_label);
        try self.generateNode(node.children.items[0]);
        try self.writer.emitJump(.GOTO, loop_label);

        try self.writer.defineLabel(&end_label);
    }

    /// Generate code for possessive question quantifier: e?+
    /// Pattern: SPLIT_POSSESSIVE consume, skip; consume: e; skip: ...
    /// Possessive = try consuming once without backtracking (greedy first)
    fn generatePossessiveQuestion(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        var skip_label = try self.writer.createLabel();
        var consume_label = try self.writer.createLabel();

        // SPLIT_POSSESSIVE: Try greedy path (consume) first, no backtracking
        try self.writer.emitSplit(.SPLIT_POSSESSIVE, consume_label, skip_label);

        // Define consume label immediately (fall-through)
        try self.writer.defineLabel(&consume_label);
        try self.generateNode(node.children.items[0]);

        // Define skip label (after the character)
        try self.writer.defineLabel(&skip_label);
    }

    // =========================================================================
    // Structural
    // =========================================================================

    /// Generate code for sequence: abc
    fn generateSequence(self: *Self, node: *Node) !void {
        for (node.children.items) |child| {
            try self.generateNode(child);
        }
    }

    /// Generate code for alternation: a|b
    /// Pattern: SPLIT L_left, L_right; L_left: a; GOTO end; L_right: b; end:
    fn generateAlternation(self: *Self, node: *Node) !void {
        if (node.children.items.len != 2) {
            return error.InvalidPattern;
        }

        var left_label = try self.writer.createLabel();
        var right_label = try self.writer.createLabel();
        var end_label = try self.writer.createLabel();

        // Split to both branches
        try self.writer.emitSplit(.SPLIT, left_label, right_label);

        // Left branch
        try self.writer.defineLabel(&left_label);
        try self.generateNode(node.children.items[0]);
        try self.writer.emitJump(.GOTO, end_label);

        // Right branch
        try self.writer.defineLabel(&right_label);
        try self.generateNode(node.children.items[1]);

        try self.writer.defineLabel(&end_label);
    }

    /// Generate code for capture group: (...)
    fn generateGroup(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        const group_index = node.group_index;

        // SAVE_START
        try self.writer.emit1(.SAVE_START, group_index);

        // Generate group content
        try self.generateNode(node.children.items[0]);

        // SAVE_END
        try self.writer.emit1(.SAVE_END, group_index);
    }

    /// Generate code for a non-capturing group (?:...)
    /// Non-capturing groups only provide grouping without capturing
    fn generateNonCapturingGroup(self: *Self, node: *Node) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        // Just generate the content without SAVE_START/SAVE_END
        // This is purely for grouping (e.g., for quantifiers or alternation)
        try self.generateNode(node.children.items[0]);
    }

    // =========================================================================
    // Anchors
    // =========================================================================

    fn generateAnchorStart(self: *Self) !void {
        try self.writer.emitSimple(.LINE_START);
    }

    fn generateAnchorEnd(self: *Self) !void {
        try self.writer.emitSimple(.LINE_END);
    }

    fn generateWordBoundary(self: *Self) !void {
        try self.writer.emitSimple(.WORD_BOUNDARY);
    }

    fn generateNotWordBoundary(self: *Self) !void {
        try self.writer.emitSimple(.NOT_WORD_BOUNDARY);
    }

    /// Generate code for backreference
    fn generateBackRef(self: *Self, node: *Node) !void {
        const group = node.group_index;

        // Choose case-sensitive or case-insensitive based on options
        const opcode: opcodes.Opcode = if (self.options.case_insensitive)
            .BACK_REF_I
        else
            .BACK_REF;

        try self.writer.emit1(opcode, group);
    }

    /// Generate code for lookahead assertion
    fn generateLookahead(self: *Self, node: *Node, negative: bool) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        const opcode: opcodes.Opcode = if (negative) .NEGATIVE_LOOKAHEAD else .LOOKAHEAD;

        // For simplicity, we don't use the length field for now
        // The executor will find LOOKAHEAD_END by scanning forward
        try self.writer.emit1(opcode, 0);

        // Generate the lookahead pattern
        try self.generateNode(node.children.items[0]);

        // Emit lookahead end marker
        try self.writer.emitSimple(.LOOKAHEAD_END);
    }

    /// Generate code for lookbehind assertion: (?<=...) or (?<!...)
    fn generateLookbehind(self: *Self, node: *Node, negative: bool) !void {
        if (node.children.items.len != 1) {
            return error.InvalidPattern;
        }

        const opcode: opcodes.Opcode = if (negative) .NEGATIVE_LOOKBEHIND else .LOOKBEHIND;

        // For simplicity, we don't use the length field for now
        // The executor will find LOOKBEHIND_END by scanning forward
        try self.writer.emit1(opcode, 0);

        // Generate the lookbehind pattern
        try self.generateNode(node.children.items[0]);

        // Emit lookbehind end marker
        try self.writer.emitSimple(.LOOKBEHIND_END);
    }
};

// =============================================================================
// Tests
// =============================================================================

test "CodeGenerator: simple character" {
    const parser_mod = @import("../parser/parser.zig");
    const lexer_mod = @import("../parser/lexer.zig");

    const pattern = "a";
    var lexer = lexer_mod.Lexer.init(pattern);
    var parser = try parser_mod.Parser.init(std.testing.allocator, &lexer);

    const ast_root = try parser.parse();
    defer ast_root.deinit();

    var writer = BytecodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    var gen = CodeGenerator.init(std.testing.allocator, &writer, .{});
    try gen.generate(ast_root);

    const code = try writer.finalize();
    // Note: code is owned by writer, will be freed by writer.deinit()

    // Should contain CHAR32 and MATCH
    try std.testing.expect(code.len > 0);
    try std.testing.expectEqual(@intFromEnum(Opcode.CHAR32), code[0]);
}

test "CodeGenerator: sequence" {
    const parser_mod = @import("../parser/parser.zig");
    const lexer_mod = @import("../parser/lexer.zig");

    const pattern = "abc";
    var lexer = lexer_mod.Lexer.init(pattern);
    var parser = try parser_mod.Parser.init(std.testing.allocator, &lexer);

    const ast_root = try parser.parse();
    defer ast_root.deinit();

    var writer = BytecodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    var gen = CodeGenerator.init(std.testing.allocator, &writer, .{});
    try gen.generate(ast_root);

    const code = try writer.finalize();

    // Should contain 3 CHAR32 instructions + MATCH
    try std.testing.expect(code.len > 0);
}

test "CodeGenerator: alternation" {
    const parser_mod = @import("../parser/parser.zig");
    const lexer_mod = @import("../parser/lexer.zig");

    const pattern = "a|b";
    var lexer = lexer_mod.Lexer.init(pattern);
    var parser = try parser_mod.Parser.init(std.testing.allocator, &lexer);

    const ast_root = try parser.parse();
    defer ast_root.deinit();

    var writer = BytecodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    var gen = CodeGenerator.init(std.testing.allocator, &writer, .{});
    try gen.generate(ast_root);

    const code = try writer.finalize();

    // Should contain SPLIT instruction
    try std.testing.expect(code.len > 0);
}

test "CodeGenerator: star quantifier" {
    const parser_mod = @import("../parser/parser.zig");
    const lexer_mod = @import("../parser/lexer.zig");

    const pattern = "a*";
    var lexer = lexer_mod.Lexer.init(pattern);
    var parser = try parser_mod.Parser.init(std.testing.allocator, &lexer);

    const ast_root = try parser.parse();
    defer ast_root.deinit();

    var writer = BytecodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    var gen = CodeGenerator.init(std.testing.allocator, &writer, .{});
    try gen.generate(ast_root);

    const code = try writer.finalize();

    try std.testing.expect(code.len > 0);
}

test "CodeGenerator: plus quantifier" {
    const parser_mod = @import("../parser/parser.zig");
    const lexer_mod = @import("../parser/lexer.zig");

    const pattern = "a+";
    var lexer = lexer_mod.Lexer.init(pattern);
    var parser = try parser_mod.Parser.init(std.testing.allocator, &lexer);

    const ast_root = try parser.parse();
    defer ast_root.deinit();

    var writer = BytecodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    var gen = CodeGenerator.init(std.testing.allocator, &writer, .{});
    try gen.generate(ast_root);

    const code = try writer.finalize();

    try std.testing.expect(code.len > 0);
}

test "CodeGenerator: group" {
    const parser_mod = @import("../parser/parser.zig");
    const lexer_mod = @import("../parser/lexer.zig");

    const pattern = "(ab)";
    var lexer = lexer_mod.Lexer.init(pattern);
    var parser = try parser_mod.Parser.init(std.testing.allocator, &lexer);

    const ast_root = try parser.parse();
    defer ast_root.deinit();

    var writer = BytecodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    var gen = CodeGenerator.init(std.testing.allocator, &writer, .{});
    try gen.generate(ast_root);

    const code = try writer.finalize();

    // Should contain SAVE_START and SAVE_END
    try std.testing.expect(code.len > 0);
}

test "CodeGenerator: anchors" {
    const parser_mod = @import("../parser/parser.zig");
    const lexer_mod = @import("../parser/lexer.zig");

    const pattern = "^a$";
    var lexer = lexer_mod.Lexer.init(pattern);
    var parser = try parser_mod.Parser.init(std.testing.allocator, &lexer);

    const ast_root = try parser.parse();
    defer ast_root.deinit();

    var writer = BytecodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    var gen = CodeGenerator.init(std.testing.allocator, &writer, .{});
    try gen.generate(ast_root);

    const code = try writer.finalize();

    try std.testing.expect(code.len > 0);
}

test "CodeGenerator: dot" {
    const parser_mod = @import("../parser/parser.zig");
    const lexer_mod = @import("../parser/lexer.zig");

    const pattern = ".";
    var lexer = lexer_mod.Lexer.init(pattern);
    var parser = try parser_mod.Parser.init(std.testing.allocator, &lexer);

    const ast_root = try parser.parse();
    defer ast_root.deinit();

    var writer = BytecodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    var gen = CodeGenerator.init(std.testing.allocator, &writer, .{});
    try gen.generate(ast_root);

    const code = try writer.finalize();

    try std.testing.expectEqual(@intFromEnum(Opcode.CHAR), code[0]);
}

test "CodeGenerator: repeat quantifier" {
    const parser_mod = @import("../parser/parser.zig");
    const lexer_mod = @import("../parser/lexer.zig");

    const pattern = "a{2,4}";
    var lexer = lexer_mod.Lexer.init(pattern);
    var parser = try parser_mod.Parser.init(std.testing.allocator, &lexer);

    const ast_root = try parser.parse();
    defer ast_root.deinit();

    var writer = BytecodeWriter.init(std.testing.allocator);
    defer writer.deinit();

    var gen = CodeGenerator.init(std.testing.allocator, &writer, .{});
    try gen.generate(ast_root);

    const code = try writer.finalize();

    try std.testing.expect(code.len > 0);
}
