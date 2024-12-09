const str = @import("./smartString.zig");
pub const SmartString = str.SmartString;

pub const niceTypeName = @import("./niceTypeName.zig").niceTypeName;

comptime {
    const std = @import("std");
    const builtin = @import("builtin");

    if (builtin.is_test) {
        std.mem.doNotOptimizeAway(str);
    }
}
