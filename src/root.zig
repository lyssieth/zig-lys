const std = @import("std");

pub const args = @import("./args/args.zig");
pub const log = @import("./log/logging.zig");
pub const util = @import("./util/utils.zig");

comptime {
    // A hack to prevent the compiler from optimizing tests and "exports" away.
    // but only in `test` mode. Hopefully.
    const builtin = @import("builtin");

    if (builtin.is_test) {
        std.mem.doNotOptimizeAway(args);

        std.mem.doNotOptimizeAway(log);

        std.mem.doNotOptimizeAway(util);
    }
}
