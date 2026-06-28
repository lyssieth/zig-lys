const std = @import("std");

pub const SmartString = @import("SmartString.zig");
pub const niceTypeName = @import("niceTypeName.zig").niceTypeName;

test {
    std.mem.doNotOptimizeAway(SmartString);
    std.mem.doNotOptimizeAway(niceTypeName);
}
