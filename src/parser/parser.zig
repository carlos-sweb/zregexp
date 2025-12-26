//! Recursive descent parser for regex patterns
//!
//! This module implements a parser that converts tokens from the lexer
//! into an Abstract Syntax Tree (AST).
//!
//! Grammar (precedence from lowest to highest):
//!   pattern      ::= alternation
//!   alternation  ::= sequence ('|' sequence)*
//!   sequence     ::= term*
//!   term         ::= atom quantifier?
//!   quantifier   ::= '*' | '+' | '?' | '{' n (',' m?)? '}'
//!   atom         ::= char | '.' | group | charclass | anchor | escape
//!   group        ::= '(' pattern ')'
//!   charclass    ::= '[' '^'? charclass_item+ ']'
//!   charclass_item ::= char | char '-' char
//!   anchor       ::= '^' | '$' | '\b' | '\B'

const std = @import("std");
const Allocator = std.mem.Allocator;
const lexer_mod = @import("lexer.zig");
const ast_mod = @import("ast.zig");

const Lexer = lexer_mod.Lexer;
const Token = lexer_mod.Token;
const TokenType = lexer_mod.TokenType;
const Node = ast_mod.Node;
const NodeType = ast_mod.NodeType;

/// Parse error with position information
pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEOF,
    UnmatchedParen,
    UnmatchedBracket,
    InvalidCharRange,
    EmptyCharClass,
    InvalidQuantifier,
    EmptyGroup,
    EmptyAlternation,
    OutOfMemory,
    // Lexer errors
    InvalidEscape,
    InvalidRepeat,
    UnterminatedRepeat,
};

/// Parser for regex patterns
pub const Parser = struct {
    allocator: Allocator,
    lexer: *Lexer,
    current_token: Token,
    group_counter: u8,

    const Self = @This();

    /// Initialize a new parser
    pub fn init(allocator: Allocator, lexer: *Lexer) !Self {
        var self = Self{
            .allocator = allocator,
            .lexer = lexer,
            .current_token = undefined,
            .group_counter = 0,
        };
        // Prime the parser with the first token
        try self.advance();
        return self;
    }

    /// Parse a complete regex pattern
    pub fn parse(self: *Self) !*Node {
        const root = try self.parseAlternation();

        // Ensure we consumed all tokens
        if (self.current_token.type != .eof) {
            root.deinit();
            return error.UnexpectedToken;
        }

        return root;
    }

    /// Advance to the next token
    fn advance(self: *Self) !void {
        self.current_token = try self.lexer.next();
    }

    /// Check if current token matches expected type
    fn check(self: Self, token_type: TokenType) bool {
        return self.current_token.type == token_type;
    }

    /// Consume token if it matches, otherwise error
    fn consume(self: *Self, token_type: TokenType) !Token {
        if (!self.check(token_type)) {
            return error.UnexpectedToken;
        }
        const token = self.current_token;
        try self.advance();
        return token;
    }

    /// Match and consume if token matches
    fn match(self: *Self, token_type: TokenType) !bool {
        if (self.check(token_type)) {
            try self.advance();
            return true;
        }
        return false;
    }

    // =========================================================================
    // Grammar Rules (Top-Down by Precedence)
    // =========================================================================

    /// Parse alternation: sequence ('|' sequence)*
    fn parseAlternation(self: *Self) ParseError!*Node {
        var left = try self.parseSequence();
        errdefer left.deinit();

        if (self.check(.pipe)) {
            // We have alternation
            try self.advance(); // consume '|'

            var right = try self.parseSequence();
            errdefer right.deinit();

            var alt = try Node.createAlternation(self.allocator, left, right);

            // Handle multiple alternations: a|b|c -> (a|(b|c))
            while (self.check(.pipe)) {
                try self.advance(); // consume '|'

                const next = try self.parseSequence();
                errdefer next.deinit();

                alt = try Node.createAlternation(self.allocator, alt, next);
            }

            return alt;
        }

        return left;
    }

    /// Parse sequence: term*
    fn parseSequence(self: *Self) ParseError!*Node {
        var seq = try Node.createSequence(self.allocator);
        errdefer seq.deinit();

        while (true) {
            // Check for sequence terminators
            if (self.check(.pipe) or self.check(.rparen) or self.check(.eof)) {
                break;
            }

            const term = try self.parseTerm();
            errdefer term.deinit();

            try seq.appendChild(term);
        }

        // If sequence has only one child, return the child directly
        if (seq.children.items.len == 1) {
            const child = seq.children.items[0];
            seq.children.clearRetainingCapacity();
            seq.deinit();
            return child;
        }

        // Empty sequence is valid (matches empty string)
        return seq;
    }

    /// Parse term: atom quantifier?
    fn parseTerm(self: *Self) ParseError!*Node {
        const atom = try self.parseAtom();
        errdefer atom.deinit();

        // Check for quantifier (greedy)
        if (self.check(.star)) {
            try self.advance();
            return Node.createQuantifier(self.allocator, .star, atom);
        } else if (self.check(.plus)) {
            try self.advance();
            return Node.createQuantifier(self.allocator, .plus, atom);
        } else if (self.check(.question)) {
            try self.advance();
            return Node.createQuantifier(self.allocator, .question, atom);
        } else if (self.check(.repeat)) {
            const token = self.current_token;
            try self.advance();
            // Check if followed by '?' for lazy quantifier
            if (self.check(.question)) {
                try self.advance();
                return Node.createLazyRepeat(self.allocator, atom, token.repeat_min, token.repeat_max);
            }
            return Node.createRepeat(self.allocator, atom, token.repeat_min, token.repeat_max);
        }
        // Check for lazy quantifiers
        else if (self.check(.lazy_star)) {
            try self.advance();
            return Node.createQuantifier(self.allocator, .lazy_star, atom);
        } else if (self.check(.lazy_plus)) {
            try self.advance();
            return Node.createQuantifier(self.allocator, .lazy_plus, atom);
        } else if (self.check(.lazy_question)) {
            try self.advance();
            return Node.createQuantifier(self.allocator, .lazy_question, atom);
        }
        // Check for possessive quantifiers
        else if (self.check(.possessive_star)) {
            try self.advance();
            return Node.createQuantifier(self.allocator, .possessive_star, atom);
        } else if (self.check(.possessive_plus)) {
            try self.advance();
            return Node.createQuantifier(self.allocator, .possessive_plus, atom);
        } else if (self.check(.possessive_question)) {
            try self.advance();
            return Node.createQuantifier(self.allocator, .possessive_question, atom);
        }

        return atom;
    }

    /// Parse atom: char | '.' | group | charclass | anchor | escape
    fn parseAtom(self: *Self) ParseError!*Node {
        switch (self.current_token.type) {
            // Simple character
            .char => {
                const c = self.current_token.char_value;
                try self.advance();
                return Node.createChar(self.allocator, c);
            },

            // Escaped character
            .escaped_char => {
                const c = self.current_token.char_value;
                try self.advance();
                return Node.createChar(self.allocator, c);
            },

            // Dot (any character)
            .dot => {
                try self.advance();
                return Node.createDot(self.allocator);
            },

            // Character classes
            .digit => {
                try self.advance();
                // \d is equivalent to [0-9]
                return Node.createCharRange(self.allocator, '0', '9');
            },

            .word => {
                try self.advance();
                // \w - for simplicity, create a char class node
                // In full implementation, this would be [a-zA-Z0-9_]
                const class = try Node.createCharClass(self.allocator);
                try class.appendChild(try Node.createCharRange(self.allocator, 'a', 'z'));
                try class.appendChild(try Node.createCharRange(self.allocator, 'A', 'Z'));
                try class.appendChild(try Node.createCharRange(self.allocator, '0', '9'));
                try class.appendChild(try Node.createChar(self.allocator, '_'));
                return class;
            },

            .whitespace => {
                try self.advance();
                // \s is [ \t\n\r\f\v]
                const class = try Node.createCharClass(self.allocator);
                try class.appendChild(try Node.createChar(self.allocator, ' '));
                try class.appendChild(try Node.createChar(self.allocator, '\t'));
                try class.appendChild(try Node.createChar(self.allocator, '\n'));
                try class.appendChild(try Node.createChar(self.allocator, '\r'));
                return class;
            },

            // Negated character classes
            .not_digit => {
                try self.advance();
                // \D is equivalent to [^0-9]
                const node = try Node.createCharRange(self.allocator, '0', '9');
                node.inverted = true;
                return node;
            },

            .not_word => {
                try self.advance();
                // \W is [^a-zA-Z0-9_]
                const class = try Node.createCharClass(self.allocator);
                class.inverted = true;
                try class.appendChild(try Node.createCharRange(self.allocator, 'a', 'z'));
                try class.appendChild(try Node.createCharRange(self.allocator, 'A', 'Z'));
                try class.appendChild(try Node.createCharRange(self.allocator, '0', '9'));
                try class.appendChild(try Node.createChar(self.allocator, '_'));
                return class;
            },

            .not_whitespace => {
                try self.advance();
                // \S is [^ \t\n\r\f\v]
                const class = try Node.createCharClass(self.allocator);
                class.inverted = true;
                try class.appendChild(try Node.createChar(self.allocator, ' '));
                try class.appendChild(try Node.createChar(self.allocator, '\t'));
                try class.appendChild(try Node.createChar(self.allocator, '\n'));
                try class.appendChild(try Node.createChar(self.allocator, '\r'));
                return class;
            },

            // Anchors
            .line_start => {
                try self.advance();
                return Node.createAnchor(self.allocator, .anchor_start);
            },

            .line_end => {
                try self.advance();
                return Node.createAnchor(self.allocator, .anchor_end);
            },

            .word_boundary => {
                try self.advance();
                return Node.createAnchor(self.allocator, .word_boundary);
            },

            .not_word_boundary => {
                try self.advance();
                return Node.createAnchor(self.allocator, .not_word_boundary);
            },

            // Groups
            .lparen => {
                try self.advance(); // consume '('

                self.group_counter += 1;
                const group_index = self.group_counter;

                const inner = try self.parseAlternation();
                errdefer inner.deinit();

                _ = try self.consume(.rparen);

                return Node.createGroup(self.allocator, inner, group_index);
            },

            // Positive lookahead (?=...)
            .lookahead_start => {
                try self.advance(); // consume '(?='

                const inner = try self.parseAlternation();
                errdefer inner.deinit();

                _ = try self.consume(.rparen);

                return Node.createLookahead(self.allocator, inner, false);
            },

            // Negative lookahead (?!...)
            .negative_lookahead_start => {
                try self.advance(); // consume '(?!'

                const inner = try self.parseAlternation();
                errdefer inner.deinit();

                _ = try self.consume(.rparen);

                return Node.createLookahead(self.allocator, inner, true);
            },

            // Non-capturing group (?:...)
            .non_capturing_group_start => {
                try self.advance(); // consume '(?:'

                const inner = try self.parseAlternation();
                errdefer inner.deinit();

                _ = try self.consume(.rparen);

                // Note: We don't increment group_counter for non-capturing groups
                return Node.createNonCapturingGroup(self.allocator, inner);
            },

            // Positive lookbehind (?<=...)
            .lookbehind_start => {
                try self.advance(); // consume '(?<='

                const inner = try self.parseAlternation();
                errdefer inner.deinit();

                _ = try self.consume(.rparen);

                return Node.createLookbehind(self.allocator, inner, false);
            },

            // Negative lookbehind (?<!...)
            .negative_lookbehind_start => {
                try self.advance(); // consume '(?<!'

                const inner = try self.parseAlternation();
                errdefer inner.deinit();

                _ = try self.consume(.rparen);

                return Node.createLookbehind(self.allocator, inner, true);
            },

            // Character class
            .lbracket => {
                return self.parseCharClass();
            },

            // Backreference
            .back_ref => {
                const group = self.current_token.backref_group;
                try self.advance();
                return Node.createBackRef(self.allocator, group);
            },

            else => {
                return error.UnexpectedToken;
            },
        }
    }

    /// Parse character class: '[' '^'? charclass_item+ ']'
    fn parseCharClass(self: *Self) ParseError!*Node {
        _ = try self.consume(.lbracket);

        // Check for negation (^ at the start of character class)
        // Note: lexer tokenizes ^ as line_start, so we check for that
        var inverted = false;
        if (self.check(.line_start)) {
            try self.advance();
            inverted = true;
        }

        const class = try Node.createCharClass(self.allocator);
        errdefer class.deinit();
        class.inverted = inverted;

        while (!self.check(.rbracket) and !self.check(.eof)) {
            if (self.check(.char) or self.check(.escaped_char)) {
                const first_char = self.current_token.char_value;
                try self.advance();

                // Check for range
                if (self.check(.hyphen)) {
                    try self.advance(); // consume '-'

                    if (self.check(.char) or self.check(.escaped_char)) {
                        const last_char = self.current_token.char_value;
                        try self.advance();

                        if (last_char < first_char) {
                            return error.InvalidCharRange;
                        }

                        const range = try Node.createCharRange(self.allocator, first_char, last_char);
                        errdefer range.deinit();
                        try class.appendChild(range);
                    } else {
                        // Hyphen at end or before ']', treat as literal
                        const first = try Node.createChar(self.allocator, first_char);
                        errdefer first.deinit();
                        try class.appendChild(first);

                        const hyphen_char = try Node.createChar(self.allocator, '-');
                        errdefer hyphen_char.deinit();
                        try class.appendChild(hyphen_char);
                    }
                } else {
                    // Single character
                    const char_node = try Node.createChar(self.allocator, first_char);
                    errdefer char_node.deinit();
                    try class.appendChild(char_node);
                }
            } else if (self.check(.hyphen)) {
                // Literal hyphen
                try self.advance();
                const hyphen = try Node.createChar(self.allocator, '-');
                errdefer hyphen.deinit();
                try class.appendChild(hyphen);
            } else {
                return error.UnexpectedToken;
            }
        }

        _ = try self.consume(.rbracket);

        if (class.children.items.len == 0) {
            return error.EmptyCharClass;
        }

        return class;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "Parser: simple character" {
    const pattern = "a";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.char, root.type);
    try std.testing.expectEqual(@as(u32, 'a'), root.char_value);
}

test "Parser: sequence" {
    const pattern = "abc";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.sequence, root.type);
    try std.testing.expectEqual(@as(usize, 3), root.children.items.len);
    try std.testing.expectEqual(@as(u32, 'a'), root.children.items[0].char_value);
    try std.testing.expectEqual(@as(u32, 'b'), root.children.items[1].char_value);
    try std.testing.expectEqual(@as(u32, 'c'), root.children.items[2].char_value);
}

test "Parser: alternation" {
    const pattern = "a|b";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.alternation, root.type);
    try std.testing.expectEqual(@as(usize, 2), root.children.items.len);
    try std.testing.expectEqual(NodeType.char, root.children.items[0].type);
    try std.testing.expectEqual(NodeType.char, root.children.items[1].type);
}

test "Parser: star quantifier" {
    const pattern = "a*";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.star, root.type);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
    try std.testing.expectEqual(NodeType.char, root.children.items[0].type);
}

test "Parser: plus quantifier" {
    const pattern = "a+";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.plus, root.type);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
}

test "Parser: question quantifier" {
    const pattern = "a?";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.question, root.type);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
}

test "Parser: repeat quantifier" {
    const pattern = "a{2,5}";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.repeat, root.type);
    try std.testing.expectEqual(@as(u32, 2), root.repeat_min);
    try std.testing.expectEqual(@as(u32, 5), root.repeat_max);
}

test "Parser: dot" {
    const pattern = ".";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.dot, root.type);
}

test "Parser: anchors" {
    {
        const pattern = "^a";
        var lexer = Lexer.init(pattern);
        var parser = try Parser.init(std.testing.allocator, &lexer);
        const root = try parser.parse();
        defer root.deinit();

        try std.testing.expectEqual(NodeType.sequence, root.type);
        try std.testing.expectEqual(NodeType.anchor_start, root.children.items[0].type);
    }

    {
        const pattern = "a$";
        var lexer = Lexer.init(pattern);
        var parser = try Parser.init(std.testing.allocator, &lexer);
        const root = try parser.parse();
        defer root.deinit();

        try std.testing.expectEqual(NodeType.sequence, root.type);
        try std.testing.expectEqual(NodeType.anchor_end, root.children.items[1].type);
    }
}

test "Parser: group" {
    const pattern = "(ab)";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.group, root.type);
    try std.testing.expectEqual(@as(u8, 1), root.group_index);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);

    const inner = root.children.items[0];
    try std.testing.expectEqual(NodeType.sequence, inner.type);
}

test "Parser: character class simple" {
    const pattern = "[abc]";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.char_class, root.type);
    try std.testing.expectEqual(@as(usize, 3), root.children.items.len);
}

test "Parser: character class range" {
    const pattern = "[a-z]";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.char_class, root.type);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);

    const range = root.children.items[0];
    try std.testing.expectEqual(NodeType.char_range, range.type);
    try std.testing.expectEqual(@as(u32, 'a'), range.range_start);
    try std.testing.expectEqual(@as(u32, 'z'), range.range_end);
}

test "Parser: complex pattern" {
    // Pattern: (a|b)+
    const pattern = "(a|b)+";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.plus, root.type);

    const group = root.children.items[0];
    try std.testing.expectEqual(NodeType.group, group.type);

    const alt = group.children.items[0];
    try std.testing.expectEqual(NodeType.alternation, alt.type);
}

test "Parser: escaped characters" {
    const pattern = "\\n\\t\\.";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.sequence, root.type);
    try std.testing.expectEqual(@as(usize, 3), root.children.items.len);
}

test "Parser: digit class" {
    const pattern = "\\d";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.char_range, root.type);
    try std.testing.expectEqual(@as(u32, '0'), root.range_start);
    try std.testing.expectEqual(@as(u32, '9'), root.range_end);
}

test "Parser: multiple alternations" {
    const pattern = "a|b|c";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    // Should create nested alternations
    try std.testing.expectEqual(NodeType.alternation, root.type);
}

test "Parser: empty pattern" {
    const pattern = "";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    // Empty pattern creates empty sequence
    try std.testing.expectEqual(NodeType.sequence, root.type);
    try std.testing.expectEqual(@as(usize, 0), root.children.items.len);
}

test "Parser: unmatched paren error" {
    const pattern = "(abc";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    try std.testing.expectError(error.UnexpectedToken, parser.parse());
}

test "Parser: invalid char range" {
    const pattern = "[z-a]";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    try std.testing.expectError(error.InvalidCharRange, parser.parse());
}

test "Parser: lazy star quantifier" {
    const pattern = "a*?";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.lazy_star, root.type);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
    try std.testing.expectEqual(NodeType.char, root.children.items[0].type);
}

test "Parser: lazy plus quantifier" {
    const pattern = "a+?";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.lazy_plus, root.type);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
}

test "Parser: lazy question quantifier" {
    const pattern = "a??";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.lazy_question, root.type);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
}

test "Parser: possessive star quantifier" {
    const pattern = "a*+";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.possessive_star, root.type);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
    try std.testing.expectEqual(NodeType.char, root.children.items[0].type);
}

test "Parser: possessive plus quantifier" {
    const pattern = "a++";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.possessive_plus, root.type);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
}

test "Parser: possessive question quantifier" {
    const pattern = "a?+";
    var lexer = Lexer.init(pattern);
    var parser = try Parser.init(std.testing.allocator, &lexer);

    const root = try parser.parse();
    defer root.deinit();

    try std.testing.expectEqual(NodeType.possessive_question, root.type);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
}
