# Architecture Overview

## Philosophy

zregexp follows these core principles:

1. **Separation of Concerns**: Each subsystem is independent and testable
2. **Explicit over Implicit**: No hidden allocations, clear ownership
3. **Safety First**: Leverage Zig's compile-time guarantees
4. **Performance Aware**: Optimize hot paths without sacrificing clarity
5. **Modular Design**: Unlike libregexp's single file, organize by domain

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        USER API                             │
│  (compile, exec, match, captures, replace, split)           │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┴───────────────────┐
        │                                       │
        ▼                                       ▼
┌──────────────────┐                  ┌──────────────────┐
│    COMPILER      │                  │    EXECUTOR      │
│                  │                  │                  │
│  - Parser        │                  │  - VM            │
│  - Validator     │    Bytecode      │  - Backtracking  │
│  - Code Gen      │  ═══════════>    │  - Stack Mgmt    │
│  - Optimizer     │                  │  - Captures      │
└──────────────────┘                  └──────────────────┘
        │                                       │
        │                                       │
        ▼                                       ▼
┌──────────────────┐                  ┌──────────────────┐
│    BYTECODE      │                  │     UNICODE      │
│                  │                  │                  │
│  - Opcodes       │                  │  - CharRange     │
│  - Format        │                  │  - Properties    │
│  - Header        │                  │  - Case Folding  │
└──────────────────┘                  └──────────────────┘
        │                                       │
        │                                       │
        └───────────────────┬───────────────────┘
                            │
                            ▼
                  ┌──────────────────┐
                  │      CORE        │
                  │                  │
                  │  - Types         │
                  │  - Errors        │
                  │  - Allocators    │
                  └──────────────────┘
```

## Module Breakdown

### 1. Core (`src/core/`)

**Purpose**: Foundation types and utilities used across all modules.

**Components**:
- `types.zig`: Common types (RegexFlags, Match, CaptureGroup)
- `errors.zig`: All error types and error sets
- `allocator.zig`: Allocator wrappers and tracking
- `config.zig`: Compile-time configuration

**Key Decisions**:
- All allocations explicit via Allocator parameter
- Errors as first-class citizens (no error codes)
- Compile-time configuration for features/optimizations

**Example Types**:
```zig
pub const RegexFlags = packed struct {
    global: bool = false,
    ignore_case: bool = false,
    multiline: bool = false,
    dotall: bool = false,
    unicode: bool = false,
    sticky: bool = false,
    indices: bool = false,
    unicode_sets: bool = false,
};

pub const CompileError = error{
    SyntaxError,
    InvalidEscape,
    UnterminatedGroup,
    InvalidQuantifier,
    TooManyCaptures,
    OutOfMemory,
};
```

### 2. Compiler (`src/compiler/`)

**Purpose**: Parse regex pattern and generate bytecode.

**Components**:
- `parser.zig`: Recursive descent parser
- `ast.zig`: Abstract syntax tree nodes
- `codegen.zig`: Bytecode emission
- `optimizer.zig`: Bytecode optimization passes
- `validator.zig`: Semantic validation

**Pipeline**:
```
Pattern String → Parser → AST → Validator → CodeGen → Bytecode
                                                ↓
                                          Optimizer
```

**Key Algorithms**:
- **Recursive Descent Parsing**: Clean, maintainable, maps to spec
- **Single-Pass Code Generation**: No intermediate IR needed
- **Peephole Optimization**: Local bytecode improvements

**Parsing Strategy**:
```
parseDisjunction()
  ├─ parseAlternative()
  │   ├─ parseTerm()
  │   │   ├─ parseAtom()
  │   │   └─ parseQuantifier()
  │   └─ parseAssertion()
  └─ '|' parseAlternative()
```

**Optimization Examples**:
- Merge consecutive character matches
- Constant folding for character classes
- Dead code elimination
- Jump threading

### 3. Bytecode (`src/bytecode/`)

**Purpose**: Define bytecode format and opcodes.

**Components**:
- `opcodes.zig`: Opcode enum and metadata
- `format.zig`: Bytecode layout and header
- `writer.zig`: Bytecode writing utilities
- `reader.zig`: Bytecode reading utilities

**Bytecode Format**:
```
┌──────────────────────────────────────────┐
│ Header (8 bytes)                         │
│  [0-1] flags: u16                        │
│  [2]   capture_count: u8                 │
│  [3]   stack_size: u8                    │
│  [4-7] bytecode_len: u32                 │
├──────────────────────────────────────────┤
│ Bytecode (variable)                      │
│  [opcode][operands]...                   │
├──────────────────────────────────────────┤
│ Named Groups (optional)                  │
│  null-terminated UTF-8 strings           │
└──────────────────────────────────────────┘
```

**Opcode Categories**:
1. **Character Matching** (6 opcodes)
2. **Anchors** (8 opcodes)
3. **Control Flow** (6 opcodes)
4. **Captures** (3 opcodes)
5. **Lookaround** (4 opcodes)
6. **Backreferences** (4 opcodes)
7. **Character Classes** (4 opcodes)
8. **Utilities** (3 opcodes)

**Total**: 38 opcodes (vs libregexp's 33)

**Opcode Design**:
```zig
pub const Opcode = enum(u8) {
    // Character matching
    char = 0x01,      // Match literal char (16-bit)
    char32 = 0x02,    // Match Unicode char (32-bit)
    char_i = 0x03,    // Case-insensitive char
    char32_i = 0x04,  // Case-insensitive Unicode
    dot = 0x05,       // Match any (except \n)
    any = 0x06,       // Match any (including \n)

    // ... etc

    pub fn size(self: Opcode) u8 {
        return switch (self) {
            .char, .char_i => 3,
            .char32, .char32_i => 5,
            .dot, .any => 1,
            // ...
        };
    }
};
```

### 4. Executor (`src/executor/`)

**Purpose**: Interpret bytecode and find matches.

**Components**:
- `vm.zig`: Virtual machine core loop
- `backtrack.zig`: Backtracking engine
- `stack.zig`: Execution stack management
- `captures.zig`: Capture group handling
- `matcher.zig`: High-level matching interface

**Execution Model**:
```
┌─────────────────────┐
│  Program Counter    │ ──> Bytecode
│  Character Pointer  │ ──> Input String
│  Backtrack Stack    │
│  Capture Array      │
│  Aux Stack          │
└─────────────────────┘
```

**Stack Architecture**:
```zig
pub const StackElem = union(enum) {
    backtrack_point: struct {
        pc: u32,
        cptr: u32,
        state: BacktrackState,
    },
    saved_capture: struct {
        index: u8,
        value: ?u32,
    },
    saved_aux: struct {
        index: u8,
        value: u32,
    },
};
```

**Backtracking Strategy**:
1. **Optimistic Execution**: Try first path
2. **Save Points**: Push backtrack info on splits
3. **Failure Recovery**: Pop and restore on no-match
4. **Depth Limiting**: Prevent stack overflow
5. **Timeout Checks**: Interrupt counter (every 10k ops)

**Optimizations**:
- Static stack (32 elements) for common cases
- Stack reuse across multiple executions
- Inline hot paths (char matching, etc.)

### 5. Unicode (`src/unicode/`)

**Purpose**: Unicode support and character operations.

**Components**:
- `charrange.zig`: Efficient character range representation
- `properties.zig`: Unicode properties lookup
- `casefold.zig`: Case folding tables and logic
- `normalize.zig`: Unicode normalization
- `tables.zig`: Generated Unicode data tables

**CharRange Design**:
```zig
pub const CharRange = struct {
    // Sorted array of [start, end+1, start, end+1, ...]
    points: std.ArrayList(u32),

    pub fn addInterval(self: *CharRange, start: u32, end: u32) !void;
    pub fn union(self: *CharRange, other: CharRange) !void;
    pub fn intersect(self: *CharRange, other: CharRange) !void;
    pub fn subtract(self: *CharRange, other: CharRange) !void;
    pub fn invert(self: *CharRange) !void;
    pub fn contains(self: CharRange, ch: u32) bool;
};
```

**Unicode Property Support**:
- General Categories (Lu, Ll, Nd, etc.)
- Scripts (Latin, Greek, Cyrillic, etc.)
- Binary Properties (Alphabetic, Emoji, etc.)
- Derived Properties (ID_Start, ID_Continue)

**Data Generation**:
- Compile-time generation from UCD (Unicode Character Database)
- Compressed tables using ranges
- ~249KB of data (similar to libregexp)

**Case Folding**:
```
Simple:   'A' → 'a'
Full:     'ß' → "ss"
Turkic:   'I' → 'ı' (dotless)
```

### 6. Utils (`src/utils/`)

**Purpose**: Shared utilities.

**Components**:
- `dynbuf.zig`: Dynamic buffer (like C DynBuf)
- `bitset.zig`: Bit set operations
- `pool.zig`: Object pooling for performance
- `debug.zig`: Debug utilities and dumpers

**DynBuf** (ArrayList wrapper):
```zig
pub fn DynBuf(comptime T: type) type {
    return struct {
        list: std.ArrayList(T),

        pub fn init(allocator: Allocator) DynBuf(T);
        pub fn deinit(self: *DynBuf(T)) void;
        pub fn append(self: *DynBuf(T), item: T) !void;
        pub fn appendSlice(self: *DynBuf(T), items: []const T) !void;
    };
}
```

## Data Flow

### Compilation Flow

```
User Input
    ↓
"(\d+)-(\d+)"
    ↓
┌─────────────────┐
│     Parser      │  Tokenize and parse
└─────────────────┘
    ↓
AST:
  Sequence
    ├─ Capture(1)
    │   └─ Repeat(1+)
    │       └─ CharClass(\d)
    ├─ Char('-')
    └─ Capture(2)
        └─ Repeat(1+)
            └─ CharClass(\d)
    ↓
┌─────────────────┐
│   Validator     │  Check semantics
└─────────────────┘
    ↓
┌─────────────────┐
│    CodeGen      │  Emit bytecode
└─────────────────┘
    ↓
Bytecode:
  [SAVE_START, 1]
  [PUSH_I32, 1]
  [RANGE, [\d]]
  [LOOP, ...]
  [SAVE_END, 1]
  [CHAR, '-']
  [SAVE_START, 2]
  ...
    ↓
┌─────────────────┐
│   Optimizer     │  Optimize
└─────────────────┘
    ↓
Optimized Bytecode
    ↓
CompiledRegex
```

### Execution Flow

```
Input: "123-456"
    ↓
┌─────────────────┐
│       VM        │
└─────────────────┘
    ↓
PC=0, CP=0  [SAVE_START, 1]  → captures[0] = 0
PC=2, CP=0  [PUSH_I32, 1]    → push(1)
PC=8, CP=0  [RANGE, \d]      → match '1', CP=1
PC=8, CP=1  [LOOP]           → counter--, goto RANGE
PC=8, CP=1  [RANGE, \d]      → match '2', CP=2
PC=8, CP=2  [LOOP]           → counter--, goto RANGE
PC=8, CP=2  [RANGE, \d]      → match '3', CP=3
PC=8, CP=3  [LOOP]           → counter--, goto RANGE
PC=8, CP=3  [RANGE, \d]      → no match '-'
PC=..       [try next path]
    ↓
    ... continue matching ...
    ↓
PC=X, CP=7  [MATCH]          → SUCCESS!
    ↓
Match {
    start: 0,
    end: 7,
    captures: [
        (0, 3),  // "123"
        (4, 7),  // "456"
    ]
}
```

## Memory Management

### Allocation Strategy

1. **Compile Time**:
   - AST nodes: Allocate during parsing
   - Bytecode: Single allocation, grown as needed
   - Temporary buffers: Arena allocator

2. **Run Time**:
   - Compiled regex: Single allocation (immutable)
   - Execution stack: Reusable, grows if needed
   - Captures: Pre-allocated array (known size)
   - Match results: Allocated on success

### Ownership Model

```zig
// User owns compiled regex
const regex = try Regex.compile(allocator, pattern, .{});
defer regex.deinit();  // User must free

// Regex owns bytecode
regex.bytecode  // Freed by regex.deinit()

// Match owns captures
const match = try regex.exec(input, allocator);
defer if (match) |m| m.deinit();  // User must free
```

### Pool Optimization (Future)

```zig
// Reuse VMs across multiple executions
var pool = try VMPool.init(allocator, 4);
defer pool.deinit();

const vm = try pool.acquire();
defer pool.release(vm);

const match = try vm.exec(regex, input);
```

## Error Handling

### Error Hierarchy

```zig
// Compile errors
pub const CompileError = error{
    SyntaxError,
    InvalidEscape,
    UnterminatedGroup,
    InvalidQuantifier,
    InvalidBackreference,
    TooManyCaptures,
    InvalidUnicodeProperty,
    OutOfMemory,
};

// Runtime errors
pub const ExecError = error{
    OutOfMemory,
    Timeout,
    StackOverflow,
};

// Combined
pub const RegexError = CompileError || ExecError;
```

### Error Context

```zig
pub const CompileErrorContext = struct {
    position: usize,
    message: []const u8,
    pattern: []const u8,
};

// Usage
catch |err| {
    if (err == error.SyntaxError) {
        const ctx = compiler.errorContext();
        std.debug.print("Error at position {}: {s}\n",
            .{ctx.position, ctx.message});
        std.debug.print("  {s}\n", .{ctx.pattern});
        std.debug.print("  {s}^\n", .{" " ** ctx.position});
    }
}
```

## Testing Strategy

### Unit Tests

Each module has comprehensive unit tests:

```zig
// src/unicode/charrange.zig
test "CharRange: add interval" {
    var cr = CharRange.init(std.testing.allocator);
    defer cr.deinit();

    try cr.addInterval('a', 'z');
    try std.testing.expect(cr.contains('m'));
    try std.testing.expect(!cr.contains('A'));
}
```

### Integration Tests

End-to-end scenarios:

```zig
// tests/integration/basic.zig
test "simple pattern matching" {
    const regex = try Regex.compile(allocator, "hello", .{});
    defer regex.deinit();

    const match = try regex.exec("hello world", allocator);
    try std.testing.expect(match != null);
    try std.testing.expectEqual(@as(usize, 0), match.?.start);
    try std.testing.expectEqual(@as(usize, 5), match.?.end);
}
```

### Property-Based Tests

Fuzzing and property testing:

```zig
test "any compiled regex is valid bytecode" {
    var prng = std.rand.DefaultPrng.init(12345);
    const random = prng.random();

    for (0..1000) |_| {
        const pattern = generateRandomPattern(random);
        const result = Regex.compile(allocator, pattern, .{});

        if (result) |regex| {
            defer regex.deinit();
            // Validate bytecode structure
            try validateBytecode(regex.bytecode);
        } else |_| {
            // Compile errors are ok
        }
    }
}
```

### Benchmark Tests

Performance tracking:

```zig
// tests/benchmarks/matching.zig
test "benchmark: email regex" {
    const pattern = "[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}";
    const regex = try Regex.compile(allocator, pattern, .{});
    defer regex.deinit();

    var timer = try std.time.Timer.start();

    for (0..10000) |_| {
        _ = try regex.exec("test@example.com", allocator);
    }

    const elapsed = timer.read();
    std.debug.print("Email regex: {} ns/op\n", .{elapsed / 10000});
}
```

## Performance Considerations

### Hot Paths

1. **Character matching**: Most common operation
   - Inline comparison
   - Branch prediction friendly

2. **Backtrack stack**: Frequent push/pop
   - Static stack for common cases
   - Cache-friendly layout

3. **Unicode lookup**: Can be expensive
   - Binary search on ranges
   - Cache frequently used results

### Cold Paths

1. **Compilation**: Happens once
   - Clarity over micro-optimizations
   - Focus on error messages

2. **Unicode normalization**: Rare
   - Correct over fast
   - Can be lazy

### Memory Layout

```zig
// Cache-friendly: related fields together
pub const VM = struct {
    // Hot: accessed every iteration
    pc: u32,
    cptr: u32,

    // Warm: accessed on operations
    stack: []StackElem,
    captures: []?u32,

    // Cold: accessed rarely
    bytecode: []const u8,
    flags: RegexFlags,
};
```

## Future Enhancements

### Phase 2: Performance

- JIT compilation (x86_64, aarch64)
- SIMD for character scanning
- Lazy DFA for simple patterns
- Compiled character classes

### Phase 3: Features

- Possessive quantifiers
- Atomic groups
- Conditional expressions
- Subroutine calls

### Phase 4: Tooling

- Regex debugger
- Pattern analyzer
- Performance profiler
- Visual bytecode viewer

---

**Document Version**: 1.0
**Last Updated**: 2025-11-26
**Status**: Living Document
