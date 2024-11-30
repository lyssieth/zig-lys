const std = @import("std");

pub const args = @import("./args/args.zig");
pub const log = @import("./log/logging.zig");

comptime {
    // A hack to prevent the compiler from optimizing tests and "exports" away.
    // but only in `test` mode. Hopefully.
    const builtin = @import("builtin");

    if (builtin.is_test) {
        std.mem.doNotOptimizeAway(args);
        std.mem.doNotOptimizeAway(args.help);

        std.mem.doNotOptimizeAway(log);
        std.mem.doNotOptimizeAway(log.init);
        std.mem.doNotOptimizeAway(log.deinit);
        std.mem.doNotOptimizeAway(log.logFn);
    }
}
