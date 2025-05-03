pub const SmartString = @import("./SmartString.zig");

const queue = @import("./queue.zig");
pub const Queue = queue.MPSCQueue;

pub const niceTypeName = @import("./niceTypeName.zig").niceTypeName;

comptime {
    const std = @import("std");
    const builtin = @import("builtin");

    if (builtin.is_test) {
        std.mem.doNotOptimizeAway(SmartString);

        std.mem.doNotOptimizeAway(queue);
        std.mem.doNotOptimizeAway(Queue);

        std.mem.doNotOptimizeAway(niceTypeName);
    }
}
