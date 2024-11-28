const std = @import("std");

pub fn niceTypeName(comptime T: type) []const u8 {
    if (T == []const u8) {
        return "string";
    }

    const name = @typeName(T);

    if (std.mem.startsWith(u8, name, "array_list.ArrayListAligned")) {
        return "array";
    }

    return name;
}

const t = std.testing;

test "nice type names" {
    try t.expectEqualStrings("string", niceTypeName([]const u8));
    try t.expectEqualStrings("array", niceTypeName(std.ArrayList(u8)));

    try t.expectEqualStrings("u8", niceTypeName(u8));
}
