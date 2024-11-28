const std = @import("std");

const log = std.log.scoped(.args);

pub const Arg = union(enum(u2)) {
    Flag: struct {
        name: []const u8,
        value: ?[]const u8,
        short: bool = false,
        consumed: bool = false,
    },
    Positional: struct {
        value: []const u8,
        idx: ?usize = undefined,
        consumed: bool = false,
    },

    pub inline fn setConsumed(s: *Arg) void {
        switch (s.*) {
            .Flag => |*f| f.consumed = true,
            .Positional => |*p| p.consumed = true,
        }
    }

    pub inline fn isConsumed(s: Arg) bool {
        return switch (s) {
            .Flag => |f| f.consumed,
            .Positional => |p| p.consumed,
        };
    }

    pub fn parse_arg(arg: []const u8) !Arg {
        var flag: ?Arg = null;
        if (std.mem.startsWith(u8, arg, "--")) {
            flag = try Arg.parse_flag(arg[2..]);
        } else if (std.mem.startsWith(u8, arg, "-")) {
            flag = try Arg.parse_flag(arg[1..]);
            flag.?.Flag.short = true;
        }

        if (flag) |f| {
            return f;
        }

        return Arg{
            .Positional = .{
                .value = arg,
            },
        };
    }

    fn parse_flag(arg: []const u8) !Arg {
        if (arg.len == 0) {
            return error.EmptyFlag;
        }

        const idx = std.mem.indexOf(u8, arg, "=");
        var flag: Arg = undefined;
        if (idx) |i| {
            const remainder = arg[i +| 1..];

            if (remainder.len == 0) {
                return error.NoValueButExpectedValue;
            }

            flag = .{
                .Flag = .{
                    .name = arg[0..i],
                    .value = arg[i +| 1..],
                },
            };
        } else {
            flag = .{ .Flag = .{
                .name = arg,
                .value = null,
            } };
        }

        switch (flag) {
            .Flag => |f| {
                if (f.name.len == 0) {
                    log.err("failed to parse flag: {s}\n", .{arg});
                    return error.InvalidFlag;
                }
            },
            .Positional => unreachable,
        }

        return flag;
    }
};
