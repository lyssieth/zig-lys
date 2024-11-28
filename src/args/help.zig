const std = @import("std");

pub fn printHelp(comptime T: type, writer: std.io.AnyWriter) !void {
    _ = T;
    _ = writer;

    return error.NotImplemented;
}
