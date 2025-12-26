//! Test aggregator for utils module
//!
//! This file imports all utils module tests to ensure they are run
//! when the main test suite is executed.

const std = @import("std");

test {
    std.testing.refAllDecls(@This());
    _ = @import("dynbuf.zig");
    _ = @import("bitset.zig");
    _ = @import("pool.zig");
    _ = @import("debug.zig");
}
