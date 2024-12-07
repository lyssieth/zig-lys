const str = @import("./smartString.zig");
pub const TrackedString = str.SmartString;

comptime {
    const std = @import("std");
    const builtin = @import("builtin");

    if (builtin.is_test) {
        std.mem.doNotOptimizeAway(str);
    }
}
