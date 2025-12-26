# Compiler Module

Parses regex patterns and generates bytecode.

## Purpose

Converts regex pattern strings into optimized bytecode for execution.

## Components

- **Parser**: Recursive descent parser for ECMAScript regex syntax
- **AST**: Abstract syntax tree representation
- **CodeGen**: Bytecode generation from AST
- **Optimizer**: Bytecode optimization passes
- **Validator**: Semantic validation

## Pipeline

```
Pattern String → Parser → AST → Validator → CodeGen → Bytecode
                                                 ↓
                                            Optimizer
```

## Files

- `parser.zig` - Regex parser
- `ast.zig` - AST definitions
- `codegen.zig` - Code generator
- `optimizer.zig` - Bytecode optimizer
- `validator.zig` - Semantic validator
- `compiler_tests.zig` - Test aggregation

## Dependencies

- `core` - Types and errors
- `bytecode` - Opcode definitions
- `unicode` - Character classes

## Status

🚧 **Not yet implemented** - Phase 2 (Weeks 4-6)
