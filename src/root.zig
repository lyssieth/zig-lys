const std = @import("std");

pub const args = @import("args/args.zig");
pub const log = @import("log/logging.zig");
pub const util = @import("util/utils.zig");

test {
    std.mem.doNotOptimizeAway(args);
    std.mem.doNotOptimizeAway(args.help);
    std.mem.doNotOptimizeAway(args.parsers);

    std.mem.doNotOptimizeAway(log);
    std.mem.doNotOptimizeAway(log.config);

    std.mem.doNotOptimizeAway(util);
}
