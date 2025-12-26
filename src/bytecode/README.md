# Bytecode Module

Defines bytecode format and opcodes.

## Purpose

Specifies the intermediate representation for compiled regex patterns.

## Components

- **Opcodes**: 38 instruction types
- **Format**: Binary bytecode layout
- **Writer**: Bytecode emission utilities
- **Reader**: Bytecode parsing utilities

## Bytecode Format

```
┌──────────────────────────────┐
│ Header (8 bytes)             │
│  [0-1] flags: u16            │
│  [2]   capture_count: u8     │
│  [3]   stack_size: u8        │
│  [4-7] bytecode_len: u32     │
├──────────────────────────────┤
│ Opcodes (variable)           │
│  [opcode][operands]...       │
├──────────────────────────────┤
│ Named Groups (optional)      │
│  null-terminated UTF-8       │
└──────────────────────────────┘
```

## Files

- `opcodes.zig` - Opcode definitions
- `format.zig` - Bytecode layout
- `writer.zig` - Bytecode writer
- `reader.zig` - Bytecode reader
- `bytecode_tests.zig` - Test aggregation

## Dependencies

- `core` - Basic types

## Status

🚧 **Not yet implemented** - Phase 2 (Week 4)
