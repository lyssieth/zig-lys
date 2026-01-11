pub const SmartString = @import("./SmartString.zig");

pub const niceTypeName = @import("./niceTypeName.zig").niceTypeName;

comptime {
    const std = @import("std");
    const builtin = @import("builtin");

    if (builtin.is_test) {
        std.mem.doNotOptimizeAway(SmartString);

        std.mem.doNotOptimizeAway(niceTypeName);
    }
}
