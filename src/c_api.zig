//! C Foreign Function Interface (FFI) for zregexp
//!
//! This module implements the C API defined in zregexp.h by wrapping the Zig regex module.
//! It handles memory management, error handling, and type conversions between C and Zig.

const std = @import("std");
const regex = @import("regex.zig");
const Regex = regex.Regex;
const MatchResult = regex.MatchResult;
const Allocator = std.mem.Allocator;

// =============================================================================
// Global State
// =============================================================================

/// Global allocator for FFI operations
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

/// Thread-local error state
threadlocal var last_error: ZRegexError = .ZREGEXP_OK;

// =============================================================================
// Opaque Type Definitions
// =============================================================================

/// Opaque handle to a compiled regular expression (maps to regex.Regex)
pub const ZRegex = Regex;

/// Opaque handle to a match result (maps to MatchResultWrapper)
pub const ZMatch = struct {
    result: MatchResult,
    input: []const u8, // Need to keep input for getCapture
    // Note: No caching - strings are created on demand and must be freed by caller
};

/// Opaque handle to a list of match results
pub const ZMatchList = struct {
    matches: std.ArrayList(ZMatch),
};

// =============================================================================
// Error Codes (must match zregexp.h)
// =============================================================================

pub const ZRegexError = enum(c_int) {
    ZREGEXP_OK = 0,
    ZREGEXP_ERROR_SYNTAX = 1,
    ZREGEXP_ERROR_OUT_OF_MEMORY = 2,
    ZREGEXP_ERROR_RECURSION_LIMIT = 3,
    ZREGEXP_ERROR_STEP_LIMIT = 4,
    ZREGEXP_ERROR_INVALID_GROUP = 5,
    ZREGEXP_ERROR_UNMATCHED_PAREN = 6,
    ZREGEXP_ERROR_INVALID_RANGE = 7,
    ZREGEXP_ERROR_UNKNOWN = 8,
};

// =============================================================================
// Compilation Options (must match zregexp.h)
// =============================================================================

pub const ZRegexOptions = extern struct {
    case_insensitive: bool,
    max_recursion_depth: u32,
    max_steps: u64,
    reserved: [4]u32,
};

// =============================================================================
// Helper Functions
// =============================================================================

fn setError(err: ZRegexError) void {
    last_error = err;
}

fn clearError() void {
    last_error = .ZREGEXP_OK;
}

fn zigErrorToC(err: anytype) ZRegexError {
    return switch (err) {
        error.OutOfMemory => .ZREGEXP_ERROR_OUT_OF_MEMORY,
        error.RecursionLimitExceeded => .ZREGEXP_ERROR_RECURSION_LIMIT,
        error.StepLimitExceeded => .ZREGEXP_ERROR_STEP_LIMIT,
        error.UnmatchedParen => .ZREGEXP_ERROR_UNMATCHED_PAREN,
        error.InvalidEscape, error.InvalidQuantifier => .ZREGEXP_ERROR_SYNTAX,
        error.InvalidCharRange => .ZREGEXP_ERROR_INVALID_RANGE,
        else => .ZREGEXP_ERROR_UNKNOWN,
    };
}

fn cStringToSlice(str: [*:0]const u8) []const u8 {
    return std.mem.span(str);
}

fn sliceToCString(slice: []const u8) ![]u8 {
    // Allocate len+1 bytes as a regular slice
    const buf = try allocator.alloc(u8, slice.len + 1);
    @memcpy(buf[0..slice.len], slice);
    buf[slice.len] = 0;
    // Return the full buffer - this will be freed with its full length
    return buf;
}

// =============================================================================
// Version Information
// =============================================================================

export fn zregexp_version() [*:0]const u8 {
    return "1.0.0";
}

// =============================================================================
// Options
// =============================================================================

export fn zregexp_default_options() ZRegexOptions {
    return .{
        .case_insensitive = false,
        .max_recursion_depth = 1000,
        .max_steps = 1000000,
        .reserved = [_]u32{0} ** 4,
    };
}

// =============================================================================
// Compilation and Destruction
// =============================================================================

export fn zregexp_compile(pattern: [*:0]const u8, options: ?*const ZRegexOptions) ?*ZRegex {
    clearError();

    const pattern_slice = cStringToSlice(pattern);

    // Compile regex
    // Note: max_recursion_depth and max_steps are runtime execution limits,
    // not compilation options. They are handled by the Matcher, not the compiler.
    const re = if (options) |opts| blk: {
        const compile_opts = @import("codegen/compiler.zig").CompileOptions{
            .case_insensitive = opts.case_insensitive,
        };
        break :blk Regex.compileWithOptions(allocator, pattern_slice, compile_opts) catch |err| {
            setError(zigErrorToC(err));
            return null;
        };
    } else blk: {
        break :blk Regex.compile(allocator, pattern_slice) catch |err| {
            setError(zigErrorToC(err));
            return null;
        };
    };

    // Allocate on heap
    const heap_re = allocator.create(Regex) catch {
        re.deinit();
        setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
        return null;
    };
    heap_re.* = re;

    return heap_re;
}

export fn zregexp_free(re: ?*ZRegex) void {
    if (re) |r| {
        r.deinit();
        allocator.destroy(r);
    }
}

// =============================================================================
// Matching Functions
// =============================================================================

export fn zregexp_find(re: *ZRegex, input: [*:0]const u8) ?*ZMatch {
    clearError();

    const input_slice = cStringToSlice(input);

    const result = re.find(input_slice) catch |err| {
        setError(zigErrorToC(err));
        return null;
    };

    if (result) |match| {
        // Duplicate input string for storage
        const input_dup = allocator.dupe(u8, input_slice) catch {
            match.deinit();
            setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
            return null;
        };

        const heap_match = allocator.create(ZMatch) catch {
            allocator.free(input_dup);
            match.deinit();
            setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
            return null;
        };

        heap_match.* = .{
            .result = match,
            .input = input_dup,
        };

        return heap_match;
    }

    return null;
}

export fn zregexp_find_all(re: *ZRegex, input: [*:0]const u8) ?*ZMatchList {
    clearError();

    const input_slice = cStringToSlice(input);

    var matches_unmanaged = re.findAll(input_slice) catch |err| {
        setError(zigErrorToC(err));
        return null;
    };

    // Convert to managed ArrayList
    var match_list = std.ArrayList(ZMatch){};

    // Duplicate input once for all matches
    const input_dup = allocator.dupe(u8, input_slice) catch {
        for (matches_unmanaged.items) |m| m.deinit();
        matches_unmanaged.deinit(allocator);
        setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
        return null;
    };

    for (matches_unmanaged.items) |match| {
        match_list.append(allocator, .{
            .result = match,
            .input = input_dup,
        }) catch {
            allocator.free(input_dup);
            for (matches_unmanaged.items) |m| m.deinit();
            matches_unmanaged.deinit(allocator);
            match_list.deinit(allocator);
            setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
            return null;
        };
    }

    matches_unmanaged.deinit(allocator);

    const heap_list = allocator.create(ZMatchList) catch {
        allocator.free(input_dup);
        match_list.deinit(allocator);
        setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
        return null;
    };

    heap_list.* = .{ .matches = match_list };
    return heap_list;
}

export fn zregexp_is_match(re: *ZRegex, input: [*:0]const u8) bool {
    clearError();

    const input_slice = cStringToSlice(input);

    const match = re.find(input_slice) catch |err| {
        setError(zigErrorToC(err));
        return false;
    };

    if (match) |m| {
        m.deinit();
        return true;
    }

    return false;
}

// =============================================================================
// Match Result Functions
// =============================================================================

export fn zregexp_match_slice(match: *ZMatch) [*:0]u8 {
    const slice = match.result.group(match.input);
    const buf = sliceToCString(slice) catch {
        setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
        return @constCast("");
    };
    // Caller must free with zregexp_string_free()
    return @ptrCast(@constCast(buf.ptr));
}

export fn zregexp_match_start(match: *ZMatch) usize {
    return match.result.start;
}

export fn zregexp_match_end(match: *ZMatch) usize {
    return match.result.end;
}

export fn zregexp_match_group(match: *ZMatch, group_index: u8) ?[*:0]u8 {
    if (group_index >= 10) {
        setError(.ZREGEXP_ERROR_INVALID_GROUP);
        return null;
    }

    const capture = match.result.getCapture(group_index, match.input) orelse return null;

    const buf = sliceToCString(capture) catch {
        setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
        return null;
    };

    // Caller must free with zregexp_string_free()
    return @ptrCast(@constCast(buf.ptr));
}

export fn zregexp_match_free(match: ?*ZMatch) void {
    if (match) |m| {
        m.result.deinit();
        allocator.free(m.input);
        allocator.destroy(m);
    }
}

// =============================================================================
// Match List Functions
// =============================================================================

export fn zregexp_match_list_count(list: *ZMatchList) usize {
    return list.matches.items.len;
}

export fn zregexp_match_list_get(list: *ZMatchList, index: usize) ?*ZMatch {
    if (index >= list.matches.items.len) {
        return null;
    }
    return &list.matches.items[index];
}

export fn zregexp_match_list_free(list: ?*ZMatchList) void {
    if (list) |l| {
        // Free input (shared by all matches in list)
        if (l.matches.items.len > 0) {
            allocator.free(l.matches.items[0].input);
        }

        // Free all match results
        for (l.matches.items) |*m| {
            m.result.deinit();
        }

        l.matches.deinit(allocator);
        allocator.destroy(l);
    }
}

// =============================================================================
// String Replacement
// =============================================================================

export fn zregexp_replace(re: *ZRegex, input: [*:0]const u8, replacement: [*:0]const u8) ?[*:0]u8 {
    clearError();

    const input_slice = cStringToSlice(input);
    const replacement_slice = cStringToSlice(replacement);

    // Find all matches
    var matches_unmanaged = re.findAll(input_slice) catch |err| {
        setError(zigErrorToC(err));
        return null;
    };
    defer {
        for (matches_unmanaged.items) |m| m.deinit();
        matches_unmanaged.deinit(allocator);
    }

    if (matches_unmanaged.items.len == 0) {
        // No matches, return copy of input
        const buf = sliceToCString(input_slice) catch {
            setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
            return null;
        };
        return @ptrCast(@constCast(buf.ptr));
    }

    // Build result string
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var last_end: usize = 0;

    for (matches_unmanaged.items) |match| {
        // Append text before match
        result.appendSlice(allocator, input_slice[last_end..match.start]) catch {
            setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
            return null;
        };

        // Append replacement
        result.appendSlice(allocator, replacement_slice) catch {
            setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
            return null;
        };

        last_end = match.end;
    }

    // Append remaining text
    result.appendSlice(allocator, input_slice[last_end..]) catch {
        setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
        return null;
    };

    // Convert to C string
    const buf = sliceToCString(result.items) catch {
        setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
        return null;
    };

    return @ptrCast(@constCast(buf.ptr));
}

export fn zregexp_string_free(str: ?[*:0]u8) void {
    if (str) |s| {
        // Reconstruct the full buffer (len + 1 for null)
        const len = std.mem.len(s);
        const buf: []u8 = @constCast(@as([*]u8, @ptrCast(s))[0..len+1]);
        allocator.free(buf);
    }
}

// =============================================================================
// Error Handling
// =============================================================================

export fn zregexp_last_error() ZRegexError {
    return last_error;
}

export fn zregexp_error_message(err: ZRegexError) [*:0]const u8 {
    return switch (err) {
        .ZREGEXP_OK => "No error",
        .ZREGEXP_ERROR_SYNTAX => "Syntax error in pattern",
        .ZREGEXP_ERROR_OUT_OF_MEMORY => "Out of memory",
        .ZREGEXP_ERROR_RECURSION_LIMIT => "Recursion depth limit exceeded",
        .ZREGEXP_ERROR_STEP_LIMIT => "Execution step limit exceeded",
        .ZREGEXP_ERROR_INVALID_GROUP => "Invalid capture group number",
        .ZREGEXP_ERROR_UNMATCHED_PAREN => "Unmatched parenthesis",
        .ZREGEXP_ERROR_INVALID_RANGE => "Invalid character range",
        .ZREGEXP_ERROR_UNKNOWN => "Unknown error",
    };
}

export fn zregexp_clear_error() void {
    clearError();
}

// =============================================================================
// Utility Functions
// =============================================================================

export fn zregexp_escape(input: [*:0]const u8) ?[*:0]u8 {
    clearError();

    const input_slice = cStringToSlice(input);

    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    // Characters that need escaping in regex
    const special_chars = "\\^$.|?*+()[]{}";

    for (input_slice) |c| {
        if (std.mem.indexOfScalar(u8, special_chars, c) != null) {
            result.append(allocator, '\\') catch {
                setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
                return null;
            };
        }
        result.append(allocator, c) catch {
            setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
            return null;
        };
    }

    const buf = sliceToCString(result.items) catch {
        setError(.ZREGEXP_ERROR_OUT_OF_MEMORY);
        return null;
    };

    return @ptrCast(@constCast(buf.ptr));
}

export fn zregexp_is_valid_pattern(pattern: [*:0]const u8) bool {
    clearError();

    const pattern_slice = cStringToSlice(pattern);

    var re = Regex.compile(allocator, pattern_slice) catch {
        return false;
    };
    defer re.deinit();

    return true;
}
