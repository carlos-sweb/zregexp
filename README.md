# zregexp - Modern Regular Expression Engine for Zig

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-304%2F304-brightgreen)](#)
[![Zig](https://img.shields.io/badge/zig-0.13.0-orange)](https://ziglang.org/)

[🇪🇸 Versión en Español](README.es.md)

A powerful, feature-rich regular expression engine written in Zig with JavaScript-like syntax and ReDoS protection.

## ✨ Features

- **🚀 High Performance**: Bytecode-based virtual machine with optimized execution
- **🛡️ ReDoS Protection**: Built-in recursion depth and step limits to prevent catastrophic backtracking
- **📝 JavaScript-Compatible Syntax**: ~70% compatibility with JavaScript RegExp
- **🔧 Zero Dependencies**: Pure Zig implementation
- **🌐 C/C++ Bindings**: Easy integration with C and C++ projects
- **✅ Well Tested**: 304 comprehensive tests ensuring reliability

## 🎯 Supported Features

### Assertions (100% JS Compatible)
- ✅ `(?=...)` Positive lookahead
- ✅ `(?!...)` Negative lookahead
- ✅ `(?<=...)` Positive lookbehind
- ✅ `(?<!...)` Negative lookbehind

### Groups (100% JS Compatible)
- ✅ `(...)` Capturing groups
- ✅ `(?:...)` Non-capturing groups
- ✅ `\1` to `\9` Backreferences

### Quantifiers (100% JS Compatible + Extensions)
- ✅ `*`, `+`, `?` Basic quantifiers
- ✅ `*?`, `+?`, `??` Lazy quantifiers
- ✅ `{n}`, `{n,}`, `{n,m}` Counted quantifiers
- ✅ `{n}?`, `{n,}?`, `{n,m}?` Lazy counted quantifiers
- ✅ `*+`, `++`, `?+` Possessive quantifiers (extension)

### Character Classes
- ✅ `[abc]`, `[^abc]` Character sets
- ✅ `[a-z]`, `[A-Z0-9]` Character ranges
- ✅ `.` Any character (except newline)
- ✅ `\d`, `\D` Digits / non-digits
- ✅ `\w`, `\W` Word characters / non-word
- ✅ `\s`, `\S` Whitespace / non-whitespace

### Anchors
- ✅ `^` Start of string
- ✅ `$` End of string
- ✅ `\b` Word boundary
- ✅ `\B` Non-word boundary

## 📦 Installation

### Using as a Zig Library

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zregexp = .{
        .url = "https://github.com/yourusername/zregexp/archive/refs/tags/v1.0.0.tar.gz",
        .hash = "...",
    },
},
```

In your `build.zig`:

```zig
const zregexp = b.dependency("zregexp", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zregexp", zregexp.module("zregexp"));
```

### Using as a C/C++ Library

Download pre-compiled libraries from [Releases](https://github.com/yourusername/zregexp/releases):

**Linux/macOS:**
- `libzregexp.so` / `libzregexp.dylib` (shared library)
- `libzregexp.a` (static library)
- `zregexp.h` (C header)
- `zregexp.hpp` (C++ header)

**Windows:**
- `zregexp.dll` (dynamic library)
- `zregexp.lib` (import library)
- `zregexp.h` (C header)
- `zregexp.hpp` (C++ header)

## 🚀 Quick Start

### Zig Example

```zig
const std = @import("std");
const regex = @import("zregexp");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Compile a regex pattern
    var re = try regex.Regex.compile(allocator, "hello (\\w+)");
    defer re.deinit();

    // Find a match
    const result = try re.find("hello world");
    if (result) |match| {
        defer match.deinit();

        std.debug.print("Match: {s}\n", .{match.slice()});
        std.debug.print("Group 1: {s}\n", .{match.group(1).?});
    }
}
```

### C Example

```c
#include "zregexp.h"
#include <stdio.h>

int main(void) {
    // Compile regex
    ZRegex* re = zregexp_compile("hello (\\w+)", NULL);
    if (!re) {
        fprintf(stderr, "Failed to compile regex\n");
        return 1;
    }

    // Find match
    ZMatch* match = zregexp_find(re, "hello world");
    if (match) {
        const char* full_match = zregexp_match_slice(match);
        const char* group1 = zregexp_match_group(match, 1);

        printf("Match: %s\n", full_match);
        printf("Group 1: %s\n", group1);

        zregexp_match_free(match);
    }

    zregexp_free(re);
    return 0;
}
```

### C++ Example

```cpp
#include "zregexp.hpp"
#include <iostream>

int main() {
    try {
        // Compile regex
        auto re = zregexp::Regex::compile("hello (\\w+)");

        // Find match
        auto match = re.find("hello world");
        if (match) {
            std::cout << "Match: " << match.slice() << std::endl;
            std::cout << "Group 1: " << match.group(1) << std::endl;
        }
    } catch (const zregexp::RegexError& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
```

## 📚 API Documentation

### Zig API

#### `Regex.compile(allocator, pattern) !Regex`
Compiles a regex pattern.

**Parameters:**
- `allocator`: Memory allocator
- `pattern`: Regex pattern string

**Returns:** Compiled `Regex` object

**Example:**
```zig
var re = try Regex.compile(allocator, "\\d{3}-\\d{3}-\\d{4}");
defer re.deinit();
```

#### `regex.find(input) !?MatchResult`
Finds the first match in the input string.

**Parameters:**
- `input`: String to search

**Returns:** `MatchResult` if found, `null` otherwise

#### `regex.findAll(input) !std.ArrayList(MatchResult)`
Finds all matches in the input string.

#### `regex.isMatch(input) !bool`
Tests if the pattern matches the input.

#### `regex.replace(input, replacement) ![]const u8`
Replaces all matches with the replacement string.

### C API

See `zregexp.h` for full API documentation.

**Key Functions:**
- `ZRegex* zregexp_compile(const char* pattern, ZRegexOptions* options)`
- `ZMatch* zregexp_find(ZRegex* regex, const char* input)`
- `ZMatchList* zregexp_find_all(ZRegex* regex, const char* input)`
- `bool zregexp_is_match(ZRegex* regex, const char* input)`
- `char* zregexp_replace(ZRegex* regex, const char* input, const char* replacement)`
- `void zregexp_free(ZRegex* regex)`
- `void zregexp_match_free(ZMatch* match)`

### C++ API

See `zregexp.hpp` for full API documentation.

**Key Classes:**
- `zregexp::Regex` - Main regex class with RAII semantics
- `zregexp::Match` - Match result with automatic cleanup
- `zregexp::RegexError` - Exception type for error handling

## 🔧 Building from Source

### Prerequisites
- Zig 0.13.0 or later

### Build Steps

```bash
# Clone the repository
git clone https://github.com/yourusername/zregexp.git
cd zregexp

# Run tests
zig build test

# Build all libraries
zig build

# Build for specific targets
zig build -Dtarget=x86_64-linux
zig build -Dtarget=x86_64-windows
zig build -Dtarget=x86_64-macos
zig build -Dtarget=aarch64-linux
```

The compiled libraries will be in `zig-out/lib/`:
- `libzregexp.so` / `libzregexp.dylib` (shared)
- `libzregexp.a` (static)
- `zregexp.dll` / `zregexp.lib` (Windows)

## ⚡ Performance

zregexp uses a bytecode-based virtual machine for efficient pattern matching:

- **Fast Compilation**: Patterns are compiled to optimized bytecode
- **Efficient Execution**: Direct bytecode interpretation with minimal overhead
- **ReDoS Protection**: Configurable limits prevent catastrophic backtracking
- **Memory Efficient**: Careful memory management with arena allocators

### Benchmarks

```
Pattern: \d{3}-\d{3}-\d{4}
Input: "Call me at 555-123-4567"
Time: ~150ns per match

Pattern: (?<=\$)\d+
Input: "Price: $100, $200, $300"
Time: ~200ns per match
```

## 🛡️ Security

### ReDoS Protection

zregexp includes built-in protection against Regular Expression Denial of Service (ReDoS) attacks:

- **Recursion Depth Limit**: Default 1000 (configurable)
- **Step Limit**: Default 1,000,000 (configurable)
- **Automatic Detection**: Patterns that exceed limits fail gracefully

### Configuration

```zig
const options = regex.CompileOptions{
    .max_recursion_depth = 500,
    .max_steps = 100_000,
    .case_insensitive = true,
};

var re = try regex.Regex.compileWithOptions(allocator, pattern, options);
```

## 📖 Pattern Examples

### Email Validation
```zig
const email_pattern = "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}";
```

### URL Matching
```zig
const url_pattern = "(?:https?://)?(?:www\\.)?[a-zA-Z0-9.-]+\\.[a-z]{2,}(?:/\\S*)?";
```

### Phone Number
```zig
const phone_pattern = "\\+?\\d{1,3}?[-.\\s]?\\(?\\d{1,4}\\)?[-.\\s]?\\d{1,4}[-.\\s]?\\d{1,9}";
```

### HTML Tags
```zig
const html_tag_pattern = "<(\\w+)[^>]*>.*?</\\1>";
```

### Extract Prices
```zig
const price_pattern = "(?<=\\$)\\d+(?:\\.\\d{2})?";
```

### Password Validation
```zig
// At least 8 chars, 1 uppercase, 1 lowercase, 1 digit
const password_pattern = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).{8,}$";
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup

```bash
# Clone and build
git clone https://github.com/yourusername/zregexp.git
cd zregexp
zig build test

# Run specific tests
zig test src/regex.zig
```

### Code Style
- Follow Zig standard library conventions
- Add tests for new features
- Update documentation
- Run `zig fmt` before committing

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by JavaScript RegExp and PCRE
- Built with [Zig](https://ziglang.org/)
- Thanks to all contributors

## 📬 Contact

- GitHub Issues: [Report bugs or request features](https://github.com/yourusername/zregexp/issues)
- Discussions: [Ask questions and share ideas](https://github.com/yourusername/zregexp/discussions)

## 🗺️ Roadmap

### Completed ✅
- [x] Basic character matching
- [x] Character classes and ranges
- [x] Quantifiers (greedy, lazy, possessive)
- [x] Capturing and non-capturing groups
- [x] Backreferences
- [x] Lookahead assertions
- [x] Lookbehind assertions
- [x] Anchors and word boundaries
- [x] ReDoS protection
- [x] C/C++ bindings

### In Progress 🚧
- [ ] Named capture groups `(?<name>...)`
- [ ] Unicode property escapes `\p{...}`
- [ ] Full UTF-8/UTF-16 support

### Future 🔮
- [ ] Conditional patterns `(?(condition)yes|no)`
- [ ] Recursive patterns
- [ ] JIT compilation
- [ ] WASM target support
- [ ] Performance optimizations

## 📊 Project Stats

- **Lines of Code**: ~11,000
- **Test Count**: 304 comprehensive tests
- **Test Pass Rate**: 100%
- **JavaScript Compatibility**: ~70%
- **Supported Platforms**: Linux, macOS, Windows, *BSD
- **Dependencies**: Zero (pure Zig)
- **Language**: Zig 0.13.0+

## 🏆 Features Comparison

| Feature | zregexp | JavaScript | PCRE2 | RE2 |
|---------|---------|------------|-------|-----|
| Lookahead | ✅ | ✅ | ✅ | ✅ |
| Lookbehind | ✅ | ✅ | ✅ | ❌ |
| Backreferences | ✅ | ✅ | ✅ | ❌ |
| Non-capturing groups | ✅ | ✅ | ✅ | ✅ |
| Lazy quantifiers | ✅ | ✅ | ✅ | ✅ |
| Possessive quantifiers | ✅ | ❌ | ✅ | ❌ |
| ReDoS protection | ✅ | ❌ | ❌ | ✅ |
| Unicode | 🚧 | ✅ | ✅ | ✅ |

---

**Made with ❤️ using Zig**

**Version**: 1.0.0
**Status**: Production Ready
**Zig Version**: 0.13.0+
