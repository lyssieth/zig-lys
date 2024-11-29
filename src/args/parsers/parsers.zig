const std = @import("std");

/// A signature for a 'parse' function. It takes a string and returns an error or a value.
///
/// This function should *not* be called directly, but rather through the `parse` field of a `Marker`.
pub fn ParseSignature(comptime T: type) type {
    return *const fn (value: []const u8) anyerror!T;
}

pub const num = @import("./num.zig").num;
pub const numNullable = @import("./numNullable.zig").numNullable;
pub const boolean = @import("./boolean.zig").boolean;
pub const enumLiteral = @import("./enumLiteral.zig").enumLiteral;

test "valid parser signatures" {
    const t = std.testing;

    try t.expectEqual(ParseSignature(u8), @TypeOf(num(u8)));
    try t.expectEqual(ParseSignature(bool), @TypeOf(&boolean));

    const Enum = enum { Value, Other };
    try t.expectEqual(ParseSignature(Enum), @TypeOf(enumLiteral(Enum)));
}

comptime {
    const builtin = @import("builtin");

    if (builtin.is_test) {
        std.mem.doNotOptimizeAway(num);
        std.mem.doNotOptimizeAway(boolean);
        std.mem.doNotOptimizeAway(enumLiteral);
    }
}
