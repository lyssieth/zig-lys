const str = @import("./trackedString.zig");
pub const TrackedString = str.TrackedString;

comptime {
    const std = @import("std");
    const builtin = @import("builtin");

    if (builtin.is_test) {
        std.mem.doNotOptimizeAway(str);
    }
}
