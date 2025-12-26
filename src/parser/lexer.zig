//! Lexer for regex patterns
//!
//! This module tokenizes regex patterns into a stream of tokens
//! for consumption by the parser.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Token types in regex syntax
pub const TokenType = enum {
    // Literals
    char, // Regular character
    escaped_char, // \x

    // Character classes
    dot, // .
    digit, // \d
    not_digit, // \D
    word, // \w
    not_word, // \W
    whitespace, // \s
    not_whitespace, // \S

    // Anchors
    line_start, // ^
    line_end, // $
    word_boundary, // \b
    not_word_boundary, // \B

    // Backreferences
    back_ref, // \1, \2, ..., \9

    // Quantifiers (greedy)
    star, // *
    plus, // +
    question, // ?
    repeat, // {n,m}

    // Lazy quantifiers
    lazy_star, // *?
    lazy_plus, // +?
    lazy_question, // ??

    // Possessive quantifiers (eager/atomic)
    possessive_star, // *+
    possessive_plus, // ++
    possessive_question, // ?+

    // Groups and alternation
    lparen, // (
    rparen, // )
    pipe, // |

    // Lookahead assertions
    lookahead_start, // (?=
    negative_lookahead_start, // (?!

    // Lookbehind assertions
    lookbehind_start, // (?<=
    negative_lookbehind_start, // (?<!

    // Non-capturing groups
    non_capturing_group_start, // (?:

    // Character sets
    lbracket, // [
    rbracket, // ]
    caret, // ^ (inside brackets)
    hyphen, // - (inside brackets)

    // Special
    eof,
};

/// Token with type and associated data
pub const Token = struct {
    type: TokenType,
    position: usize,

    /// Character value (for char, escaped_char)
    char_value: u32 = 0,

    /// Repeat counts (for repeat token)
    repeat_min: u32 = 0,
    repeat_max: u32 = 0,

    /// Backreference group number (for back_ref token)
    backref_group: u8 = 0,

    /// Create a simple token
    pub fn simple(token_type: TokenType, pos: usize) Token {
        return .{ .type = token_type, .position = pos };
    }

    /// Create a character token
    pub fn char_token(c: u32, pos: usize) Token {
        return .{ .type = .char, .position = pos, .char_value = c };
    }

    /// Create an escaped character token
    pub fn escaped(c: u32, pos: usize) Token {
        return .{ .type = .escaped_char, .position = pos, .char_value = c };
    }

    /// Create a repeat token
    pub fn repeat_token(min: u32, max: u32, pos: usize) Token {
        return .{
            .type = .repeat,
            .position = pos,
            .repeat_min = min,
            .repeat_max = max,
        };
    }

    /// Create a backreference token
    pub fn backref_token(group: u8, pos: usize) Token {
        return .{
            .type = .back_ref,
            .position = pos,
            .backref_group = group,
        };
    }
};

/// Lexer for tokenizing regex patterns
pub const Lexer = struct {
    pattern: []const u8,
    pos: usize,

    const Self = @This();

    /// Initialize a new lexer
    pub fn init(pattern: []const u8) Self {
        return .{
            .pattern = pattern,
            .pos = 0,
        };
    }

    /// Get the next token
    pub fn next(self: *Self) !Token {
        if (self.pos >= self.pattern.len) {
            return Token.simple(.eof, self.pos);
        }

        const c = self.pattern[self.pos];
        const start_pos = self.pos;

        switch (c) {
            '.' => {
                self.pos += 1;
                return Token.simple(.dot, start_pos);
            },
            '^' => {
                self.pos += 1;
                return Token.simple(.line_start, start_pos);
            },
            '$' => {
                self.pos += 1;
                return Token.simple(.line_end, start_pos);
            },
            '*' => {
                self.pos += 1;
                // Check for modifiers
                if (self.pos < self.pattern.len) {
                    const next_char = self.pattern[self.pos];
                    if (next_char == '?') {
                        self.pos += 1;
                        return Token.simple(.lazy_star, start_pos);
                    } else if (next_char == '+') {
                        self.pos += 1;
                        return Token.simple(.possessive_star, start_pos);
                    }
                }
                return Token.simple(.star, start_pos);
            },
            '+' => {
                self.pos += 1;
                // Check for modifiers
                if (self.pos < self.pattern.len) {
                    const next_char = self.pattern[self.pos];
                    if (next_char == '?') {
                        self.pos += 1;
                        return Token.simple(.lazy_plus, start_pos);
                    } else if (next_char == '+') {
                        self.pos += 1;
                        return Token.simple(.possessive_plus, start_pos);
                    }
                }
                return Token.simple(.plus, start_pos);
            },
            '?' => {
                self.pos += 1;
                // Check for modifiers
                if (self.pos < self.pattern.len) {
                    const next_char = self.pattern[self.pos];
                    if (next_char == '?') {
                        self.pos += 1;
                        return Token.simple(.lazy_question, start_pos);
                    } else if (next_char == '+') {
                        self.pos += 1;
                        return Token.simple(.possessive_question, start_pos);
                    }
                }
                return Token.simple(.question, start_pos);
            },
            '|' => {
                self.pos += 1;
                return Token.simple(.pipe, start_pos);
            },
            '(' => {
                self.pos += 1;
                // Check for special groups: (?= or (?! or (?<= or (?<! or (?:
                if (self.pos < self.pattern.len and self.pattern[self.pos] == '?') {
                    // Peek ahead to see what kind of assertion/group
                    if (self.pos + 1 < self.pattern.len) {
                        const next_char = self.pattern[self.pos + 1];
                        if (next_char == '=') {
                            // Positive lookahead (?=
                            self.pos += 2; // consume '?='
                            return Token.simple(.lookahead_start, start_pos);
                        } else if (next_char == '!') {
                            // Negative lookahead (?!
                            self.pos += 2; // consume '?!'
                            return Token.simple(.negative_lookahead_start, start_pos);
                        } else if (next_char == '<') {
                            // Lookbehind: (?<= or (?<!
                            if (self.pos + 2 < self.pattern.len) {
                                const third_char = self.pattern[self.pos + 2];
                                if (third_char == '=') {
                                    // Positive lookbehind (?<=
                                    self.pos += 3; // consume '?<='
                                    return Token.simple(.lookbehind_start, start_pos);
                                } else if (third_char == '!') {
                                    // Negative lookbehind (?<!
                                    self.pos += 3; // consume '?<!'
                                    return Token.simple(.negative_lookbehind_start, start_pos);
                                }
                            }
                        } else if (next_char == ':') {
                            // Non-capturing group (?:
                            self.pos += 2; // consume '?:'
                            return Token.simple(.non_capturing_group_start, start_pos);
                        }
                    }
                    // If not recognized, treat as error or regular group
                    // For now, just consume as lparen and let parser handle it
                }
                return Token.simple(.lparen, start_pos);
            },
            ')' => {
                self.pos += 1;
                return Token.simple(.rparen, start_pos);
            },
            '[' => {
                self.pos += 1;
                return Token.simple(.lbracket, start_pos);
            },
            ']' => {
                self.pos += 1;
                return Token.simple(.rbracket, start_pos);
            },
            '-' => {
                self.pos += 1;
                return Token.simple(.hyphen, start_pos);
            },
            '{' => {
                self.pos += 1;
                return try self.parseRepeat(start_pos);
            },
            '\\' => {
                self.pos += 1;
                return try self.parseEscape(start_pos);
            },
            else => {
                self.pos += 1;
                return Token.char_token(c, start_pos);
            },
        }
    }

    /// Parse repeat quantifier {n,m}
    fn parseRepeat(self: *Self, start_pos: usize) !Token {
        var min: u32 = 0;
        var max: u32 = 0;
        var has_comma = false;

        // Parse min
        while (self.pos < self.pattern.len) {
            const c = self.pattern[self.pos];
            if (c >= '0' and c <= '9') {
                min = min * 10 + (c - '0');
                self.pos += 1;
            } else if (c == ',') {
                has_comma = true;
                self.pos += 1;
                break;
            } else if (c == '}') {
                // {n} form
                max = min;
                self.pos += 1;
                return Token.repeat_token(min, max, start_pos);
            } else {
                return error.InvalidRepeat;
            }
        }

        if (!has_comma) return error.InvalidRepeat;

        // Parse max
        while (self.pos < self.pattern.len) {
            const c = self.pattern[self.pos];
            if (c >= '0' and c <= '9') {
                max = max * 10 + (c - '0');
                self.pos += 1;
            } else if (c == '}') {
                self.pos += 1;
                // {n,} means unlimited
                if (max == 0 and self.pattern[self.pos - 2] == ',') {
                    max = std.math.maxInt(u32);
                }
                return Token.repeat_token(min, max, start_pos);
            } else {
                return error.InvalidRepeat;
            }
        }

        return error.UnterminatedRepeat;
    }

    /// Parse escape sequence
    fn parseEscape(self: *Self, start_pos: usize) !Token {
        if (self.pos >= self.pattern.len) {
            return error.InvalidEscape;
        }

        const c = self.pattern[self.pos];
        self.pos += 1;

        switch (c) {
            'd' => return Token.simple(.digit, start_pos),
            'D' => return Token.simple(.not_digit, start_pos),
            'w' => return Token.simple(.word, start_pos),
            'W' => return Token.simple(.not_word, start_pos),
            's' => return Token.simple(.whitespace, start_pos),
            'S' => return Token.simple(.not_whitespace, start_pos),
            'b' => return Token.simple(.word_boundary, start_pos),
            'B' => return Token.simple(.not_word_boundary, start_pos),
            'n' => return Token.escaped('\n', start_pos),
            'r' => return Token.escaped('\r', start_pos),
            't' => return Token.escaped('\t', start_pos),
            // Backreferences \1-\9
            '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                const group = @as(u8, c - '0');
                return Token.backref_token(group, start_pos);
            },
            '\\', '.', '*', '+', '?', '|', '(', ')', '[', ']', '{', '}', '^', '$' => {
                return Token.escaped(c, start_pos);
            },
            else => return Token.escaped(c, start_pos),
        }
    }

    /// Peek at the next token without consuming it
    pub fn peek(self: *Self) !Token {
        const saved_pos = self.pos;
        const token = try self.next();
        self.pos = saved_pos;
        return token;
    }

    /// Check if we're at end of pattern
    pub fn isAtEnd(self: Self) bool {
        return self.pos >= self.pattern.len;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "Lexer: simple characters" {
    var lexer = Lexer.init("abc");

    const t1 = try lexer.next();
    try std.testing.expectEqual(TokenType.char, t1.type);
    try std.testing.expectEqual(@as(u32, 'a'), t1.char_value);

    const t2 = try lexer.next();
    try std.testing.expectEqual(TokenType.char, t2.type);
    try std.testing.expectEqual(@as(u32, 'b'), t2.char_value);

    const t3 = try lexer.next();
    try std.testing.expectEqual(TokenType.char, t3.type);
    try std.testing.expectEqual(@as(u32, 'c'), t3.char_value);

    const eof = try lexer.next();
    try std.testing.expectEqual(TokenType.eof, eof.type);
}

test "Lexer: special characters" {
    var lexer = Lexer.init(".*|()+[]?");

    try std.testing.expectEqual(TokenType.dot, (try lexer.next()).type);
    try std.testing.expectEqual(TokenType.star, (try lexer.next()).type);
    try std.testing.expectEqual(TokenType.pipe, (try lexer.next()).type);
    try std.testing.expectEqual(TokenType.lparen, (try lexer.next()).type);
    try std.testing.expectEqual(TokenType.rparen, (try lexer.next()).type);
    try std.testing.expectEqual(TokenType.plus, (try lexer.next()).type);
    try std.testing.expectEqual(TokenType.lbracket, (try lexer.next()).type);
    try std.testing.expectEqual(TokenType.rbracket, (try lexer.next()).type);
    try std.testing.expectEqual(TokenType.question, (try lexer.next()).type);
}

test "Lexer: escape sequences" {
    var lexer = Lexer.init("\\d\\w\\s\\n\\.");

    try std.testing.expectEqual(TokenType.digit, (try lexer.next()).type);
    try std.testing.expectEqual(TokenType.word, (try lexer.next()).type);
    try std.testing.expectEqual(TokenType.whitespace, (try lexer.next()).type);

    const newline = try lexer.next();
    try std.testing.expectEqual(TokenType.escaped_char, newline.type);
    try std.testing.expectEqual(@as(u32, '\n'), newline.char_value);

    const dot = try lexer.next();
    try std.testing.expectEqual(TokenType.escaped_char, dot.type);
    try std.testing.expectEqual(@as(u32, '.'), dot.char_value);
}

test "Lexer: repeat quantifier" {
    var lexer = Lexer.init("a{3}b{2,5}c{1,}");

    _ = try lexer.next(); // 'a'
    const r1 = try lexer.next();
    try std.testing.expectEqual(TokenType.repeat, r1.type);
    try std.testing.expectEqual(@as(u32, 3), r1.repeat_min);
    try std.testing.expectEqual(@as(u32, 3), r1.repeat_max);

    _ = try lexer.next(); // 'b'
    const r2 = try lexer.next();
    try std.testing.expectEqual(TokenType.repeat, r2.type);
    try std.testing.expectEqual(@as(u32, 2), r2.repeat_min);
    try std.testing.expectEqual(@as(u32, 5), r2.repeat_max);

    _ = try lexer.next(); // 'c'
    const r3 = try lexer.next();
    try std.testing.expectEqual(TokenType.repeat, r3.type);
    try std.testing.expectEqual(@as(u32, 1), r3.repeat_min);
    try std.testing.expectEqual(@as(u32, std.math.maxInt(u32)), r3.repeat_max);
}

test "Lexer: peek" {
    var lexer = Lexer.init("ab");

    const peeked = try lexer.peek();
    try std.testing.expectEqual(TokenType.char, peeked.type);
    try std.testing.expectEqual(@as(u32, 'a'), peeked.char_value);

    // Position should not have changed
    const actual = try lexer.next();
    try std.testing.expectEqual(TokenType.char, actual.type);
    try std.testing.expectEqual(@as(u32, 'a'), actual.char_value);
}

test "Lexer: anchors" {
    var lexer = Lexer.init("^hello$");

    try std.testing.expectEqual(TokenType.line_start, (try lexer.next()).type);
    _ = try lexer.next(); // 'h'
    _ = try lexer.next(); // 'e'
    _ = try lexer.next(); // 'l'
    _ = try lexer.next(); // 'l'
    _ = try lexer.next(); // 'o'
    try std.testing.expectEqual(TokenType.line_end, (try lexer.next()).type);
}

test "Lexer: word boundaries" {
    var lexer = Lexer.init("\\bword\\B");

    try std.testing.expectEqual(TokenType.word_boundary, (try lexer.next()).type);
    _ = try lexer.next(); // 'w'
    _ = try lexer.next(); // 'o'
    _ = try lexer.next(); // 'r'
    _ = try lexer.next(); // 'd'
    try std.testing.expectEqual(TokenType.not_word_boundary, (try lexer.next()).type);
}

test "Lexer: isAtEnd" {
    var lexer = Lexer.init("a");

    try std.testing.expect(!lexer.isAtEnd());
    _ = try lexer.next();
    try std.testing.expect(lexer.isAtEnd());
}

test "Lexer: invalid repeat" {
    var lexer = Lexer.init("{abc}");

    try std.testing.expectError(error.InvalidRepeat, lexer.next());
}

test "Lexer: position tracking" {
    var lexer = Lexer.init("abc");

    const t1 = try lexer.next();
    try std.testing.expectEqual(@as(usize, 0), t1.position);

    const t2 = try lexer.next();
    try std.testing.expectEqual(@as(usize, 1), t2.position);

    const t3 = try lexer.next();
    try std.testing.expectEqual(@as(usize, 2), t3.position);
}

test "Lexer: lazy quantifiers" {
    var lexer = Lexer.init("a*?b+?c??");

    _ = try lexer.next(); // 'a'
    try std.testing.expectEqual(TokenType.lazy_star, (try lexer.next()).type);
    _ = try lexer.next(); // 'b'
    try std.testing.expectEqual(TokenType.lazy_plus, (try lexer.next()).type);
    _ = try lexer.next(); // 'c'
    try std.testing.expectEqual(TokenType.lazy_question, (try lexer.next()).type);
}

test "Lexer: distinguish greedy from lazy" {
    {
        var lexer = Lexer.init("a*");
        _ = try lexer.next(); // 'a'
        try std.testing.expectEqual(TokenType.star, (try lexer.next()).type);
    }
    {
        var lexer = Lexer.init("a*?");
        _ = try lexer.next(); // 'a'
        try std.testing.expectEqual(TokenType.lazy_star, (try lexer.next()).type);
    }
}

test "Lexer: possessive quantifiers" {
    var lexer = Lexer.init("a*+b++c?+");

    _ = try lexer.next(); // 'a'
    try std.testing.expectEqual(TokenType.possessive_star, (try lexer.next()).type);
    _ = try lexer.next(); // 'b'
    try std.testing.expectEqual(TokenType.possessive_plus, (try lexer.next()).type);
    _ = try lexer.next(); // 'c'
    try std.testing.expectEqual(TokenType.possessive_question, (try lexer.next()).type);
}

test "Lexer: distinguish greedy/lazy/possessive" {
    // Star
    {
        var lexer = Lexer.init("a*");
        _ = try lexer.next();
        try std.testing.expectEqual(TokenType.star, (try lexer.next()).type);
    }
    {
        var lexer = Lexer.init("a*?");
        _ = try lexer.next();
        try std.testing.expectEqual(TokenType.lazy_star, (try lexer.next()).type);
    }
    {
        var lexer = Lexer.init("a*+");
        _ = try lexer.next();
        try std.testing.expectEqual(TokenType.possessive_star, (try lexer.next()).type);
    }
}
