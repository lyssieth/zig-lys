const std = @import("std");

pub fn numNullable(comptime T: type) *const fn (value: []const u8) anyerror!?T {
    const container = struct {
        fn func(value: []const u8) anyerror!?T {
            return try std.fmt.parseInt(T, value, 10);
        }
    };

    return &container.func;
}
