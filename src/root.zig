const std = @import("std");

pub const args = @import("./args/args.zig");

comptime {
    // A hack to prevent the compiler from optimizing tests and "exports" away.
    // but only in `Debug` mode. Hopefully.
    const builtin = @import("builtin");

    if (builtin.is_test) {
        std.mem.doNotOptimizeAway(args);
        std.mem.doNotOptimizeAway(args.help);
    }
}
