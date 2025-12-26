# Executor Module

Interprets bytecode and finds pattern matches.

## Purpose

Executes compiled regex bytecode against input strings using backtracking.

## Components

- **VM**: Virtual machine core execution loop
- **Backtracking**: Backtracking state management
- **Stack**: Execution stack (backtrack points, captures)
- **Captures**: Capture group extraction
- **Matcher**: High-level matching API

## Execution Model

```
Bytecode + Input → VM → Backtracking → Match Result
                    ↓
                 Captures
```

## Files

- `vm.zig` - Virtual machine
- `backtrack.zig` - Backtracking engine
- `stack.zig` - Stack management
- `captures.zig` - Capture handling
- `matcher.zig` - Matching interface
- `executor_tests.zig` - Test aggregation

## Dependencies

- `core` - Types and errors
- `bytecode` - Opcode definitions
- `unicode` - Character operations

## Status

🚧 **Not yet implemented** - Phase 3 (Weeks 7-9)
