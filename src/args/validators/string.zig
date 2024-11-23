const std = @import("std");
const t = std.testing;

pub fn notEmpty(value: []const u8) anyerror!bool {
    if (value.len == 0) {
        return false;
    }

    return true;
}

test "not empty" {
    try t.expect(try notEmpty("") == false);
    try t.expect(try notEmpty("a"));
}

pub fn notWhiteSpace(value: []const u8) anyerror!bool {
    if (std.mem.trim(u8, value, " \t\n\r").len == 0) {
        return false;
    }

    return true;
}

test "not white space" {
    try t.expect(try notWhiteSpace("") == false);
    try t.expect(try notWhiteSpace("\n\r\t ") == false);
    try t.expect(try notWhiteSpace("a"));
    try t.expect(try notWhiteSpace(" a"));
    try t.expect(try notWhiteSpace("\ta"));
    try t.expect(try notWhiteSpace("\n\r\t a"));
}
