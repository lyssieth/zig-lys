const std = @import("std");

pub fn enumLiteral(comptime T: type) *const fn (value: []const u8) anyerror!T {
    const container = struct {
        fn func(value: []const u8) anyerror!T {
            return parseEnumFromStr(T, value);
        }
    };

    return &container.func;
}

fn parseEnumFromStr(comptime T: type, str: []const u8) !T {
    const info = @typeInfo(T);

    comptime {
        if (std.meta.activeTag(info) != .Enum) {
            @compileError("Expected enum type, got " ++ @typeName(T));
        }
    }

    inline for (info.Enum.fields) |field| {
        if (std.mem.eql(u8, field.name, str)) {
            return @enumFromInt(field.value);
        }
    }

    return error.InvalidEnum;
}

test "enum literal" {
    const t = std.testing;

    const Demo = enum(u8) {
        A,
        B,
    };

    try t.expectEqual(Demo.A, try parseEnumFromStr(Demo, "A"));
    try t.expectEqual(Demo.B, try parseEnumFromStr(Demo, "B"));

    try t.expectError(error.InvalidEnum, parseEnumFromStr(Demo, "DefinitelyNot"));
}
