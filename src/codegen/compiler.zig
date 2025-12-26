//! Main compiler API
//!
//! This module provides the high-level compiler interface,
//! orchestrating the lexer, parser, code generator, and optimizer.

const std = @import("std");
const Allocator = std.mem.Allocator;

const lexer_mod = @import("../parser/lexer.zig");
const parser_mod = @import("../parser/parser.zig");
const ast_mod = @import("../parser/ast.zig");
const generator_mod = @import("generator.zig");
const optimizer_mod = @import("optimizer.zig");
const bytecode_writer = @import("../bytecode/writer.zig");

const Lexer = lexer_mod.Lexer;
const Parser = parser_mod.Parser;
const CodeGenerator = generator_mod.CodeGenerator;
const Optimizer = optimizer_mod.Optimizer;
const OptLevel = optimizer_mod.OptLevel;
const BytecodeWriter = bytecode_writer.BytecodeWriter;

/// Compilation result
pub const CompileResult = struct {
    bytecode: []const u8,
    allocator: Allocator,

    /// Free the compilation result
    pub fn deinit(self: CompileResult) void {
        self.allocator.free(self.bytecode);
    }
};

/// Compiler options
pub const CompileOptions = struct {
    /// Optimization level
    opt_level: OptLevel = .basic,

    /// Case insensitive matching
    case_insensitive: bool = false,

    /// Multiline mode (^ and $ match line boundaries)
    multiline: bool = false,

    /// Dot matches newline
    dot_all: bool = false,
};

/// Compile a regex pattern to bytecode
pub fn compile(allocator: Allocator, pattern: []const u8, options: CompileOptions) !CompileResult {
    // Phase 1: Lexing
    var lexer = Lexer.init(pattern);

    // Phase 2: Parsing
    var parser = try Parser.init(allocator, &lexer);
    const ast = try parser.parse();
    defer ast.deinit();

    // Phase 3: Code generation
    var writer = BytecodeWriter.init(allocator);
    defer writer.deinit();

    var generator = CodeGenerator.init(allocator, &writer, options);
    try generator.generate(ast);

    const unoptimized = try writer.finalize();
    // Note: unoptimized is owned by writer, will be freed by writer.deinit()

    // Phase 4: Optimization
    var optimizer = Optimizer.init(allocator, options.opt_level);
    const optimized = try optimizer.optimize(unoptimized);

    return CompileResult{
        .bytecode = optimized,
        .allocator = allocator,
    };
}

/// Compile with default options
pub fn compileSimple(allocator: Allocator, pattern: []const u8) !CompileResult {
    return compile(allocator, pattern, .{});
}

// =============================================================================
// Tests
// =============================================================================

test "compile: simple character" {
    const result = try compileSimple(std.testing.allocator, "a");
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}

test "compile: sequence" {
    const result = try compileSimple(std.testing.allocator, "abc");
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}

test "compile: alternation" {
    const result = try compileSimple(std.testing.allocator, "a|b");
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}

test "compile: quantifiers" {
    {
        const result = try compileSimple(std.testing.allocator, "a*");
        defer result.deinit();
        try std.testing.expect(result.bytecode.len > 0);
    }

    {
        const result = try compileSimple(std.testing.allocator, "a+");
        defer result.deinit();
        try std.testing.expect(result.bytecode.len > 0);
    }

    {
        const result = try compileSimple(std.testing.allocator, "a?");
        defer result.deinit();
        try std.testing.expect(result.bytecode.len > 0);
    }

    {
        const result = try compileSimple(std.testing.allocator, "a{2,5}");
        defer result.deinit();
        try std.testing.expect(result.bytecode.len > 0);
    }
}

test "compile: groups" {
    const result = try compileSimple(std.testing.allocator, "(abc)");
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}

test "compile: character classes" {
    const result = try compileSimple(std.testing.allocator, "[abc]");
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}

test "compile: anchors" {
    const result = try compileSimple(std.testing.allocator, "^hello$");
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}

test "compile: complex pattern" {
    const result = try compileSimple(std.testing.allocator, "(a|b)+c*");
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}

test "compile: with options" {
    const options = CompileOptions{
        .opt_level = .aggressive,
        .case_insensitive = true,
        .multiline = true,
    };

    const result = try compile(std.testing.allocator, "test", options);
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}

test "compile: empty pattern" {
    const result = try compileSimple(std.testing.allocator, "");
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}

test "compile: dot" {
    const result = try compileSimple(std.testing.allocator, ".");
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}

test "compile: escaped characters" {
    const result = try compileSimple(std.testing.allocator, "\\n\\t");
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}

test "compile: word boundaries" {
    const result = try compileSimple(std.testing.allocator, "\\bword\\b");
    defer result.deinit();

    try std.testing.expect(result.bytecode.len > 0);
}
