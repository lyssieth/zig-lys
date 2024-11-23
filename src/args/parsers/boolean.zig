const std = @import("std");

const TrueValues = [_][]const u8{ "true", "yes", "y", "on", "1" };
const FalseValues = [_][]const u8{ "false", "no", "n", "off", "0" };

pub fn boolean(value: []const u8) anyerror!bool {
    if (value.len > 10) {
        return error.InvalidBool_ValueTooLong;
    }

    var buf: [10]u8 = undefined;
    const lower = std.ascii.lowerString(&buf, value);

    inline for (TrueValues) |true_value| {
        if (std.mem.eql(u8, lower, true_value)) {
            return true;
        }
    }

    inline for (FalseValues) |false_value| {
        if (std.mem.eql(u8, lower, false_value)) {
            return false;
        }
    }

    return error.InvalidBool;
}

test "bool parser" {
    const t = std.testing;

    const ExpectTrue = [_][]const u8{ "true", "TrUe", "TRUE", "1", "yes", "Y", "on" };
    const ExpectFalse = [_][]const u8{ "false", "FaLsE", "FALSE", "0", "no", "N", "off" };
    const ExpectError = [_][]const u8{ "wrong", "maybe", "1.0", "0.0", "truefalse" };

    inline for (ExpectTrue) |expect| {
        try t.expect(try boolean(expect) == true);
    }

    inline for (ExpectFalse) |expect| {
        try t.expect(try boolean(expect) == false);
    }

    inline for (ExpectError) |expect| {
        try t.expectError(error.InvalidBool, boolean(expect));
    }

    try t.expectError(error.InvalidBool_ValueTooLong, boolean("1234567890123456789012345678901234567890"));
}
