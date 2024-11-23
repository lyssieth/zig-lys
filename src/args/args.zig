const std = @import("std");

const Allocator = std.mem.Allocator;

pub const parsers = @import("./parsers/parsers.zig");
pub const validators = @import("./validators/validators.zig");

const Arg = @import("./arg.zig").Arg;

/// Metadata for a field that is parseable by the argument parser.
pub const Extra = union(enum(u2)) {
    Positional,
    Remainder,
    Flag: struct {
        name: []const u8,
        short: ?[]const u8 = null,
        toggle: bool = false,
        takesValue: bool = false,
    },
};

/// A marker for any field `T` that you want to be parseable by the argument parser.
pub fn Marker(comptime T: type) type {
    return struct {
        value: T,
        extra: Extra,
        /// Optional function that parses the value of the field.
        /// If this is null, no parsing will take place.
        ///
        /// This function can be any function that takes a `[]const u8` and returns `anyerror!T`.
        ///
        /// However, it is recommended to use `lys.args.parsers` for common types.
        parse: ?parsers.ParseSignature(T) = null,
        /// Optional function that validates the value of the field.
        /// If this is null, no validation will take place.
        ///
        /// This function can be any function that takes a `[]const u8` and returns `anyerror!void`.
        ///
        /// However, it is recommended to use `lys.args.validators` for common types.
        validate: ?validators.ValidateSignature = null,
    };
}

/// <https://git.cutie.zone/lyssieth/zither/issues/1>
pub fn parseArgs(comptime T: type, allocator: Allocator) !T {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    return parseArgsImpl(T, allocator, args);
}

/// actual implementation of parse_args, necessary for testing purposes.
/// The main implementation is in parse_args, which is a wrapper around this.
fn parseArgsImpl(comptime T: type, allocator: Allocator, args: [][]const u8) !T {
    var flags = std.ArrayList(Arg).init(allocator);
    defer flags.deinit();

    if (args.len < 2) {
        return error.NoArguments;
    }

    for (args, 0..) |arg, idx| {
        if (idx == 0) continue; // skip first arg: process name

        const argument = try Arg.parse_arg(arg);

        try flags.append(argument);
    }

    var i: usize = 0;
    for (0..flags.items.len) |idx| {
        const flag = &flags.items[idx];
        switch (flag.*) {
            .Positional => |*p| {
                p.idx = i;
                i += 1;
            },
            .Flag => continue,
        }
    }

    const result = initFromParsed(T, allocator, flags.items);

    return result;
}

/// helper that finds a flag by name (or short name), if it's not consumed
fn find(flags: []Arg, expected_long: []const u8, expected_short: ?[]const u8) ?*Arg {
    for (flags) |*flag| {
        if (flag.isConsumed()) continue; // skip consumed flags

        switch (flag.*) {
            .Flag => |f| {
                if (std.mem.eql(u8, f.name, expected_long)) {
                    return flag;
                }

                if (expected_short == null) continue;

                if (std.mem.eql(u8, f.name, expected_short.?)) {
                    return flag;
                }
            },
            .Positional => continue,
        }
    }

    return null;
}

/// helper that takes the next non-consumed positional argument
fn nextPositional(flags: []Arg) ?*Arg {
    for (flags) |*flag| {
        if (flag.isConsumed()) continue; // skip consumed flags

        switch (flag.*) {
            .Flag => continue,
            .Positional => |_| {
                return flag;
            },
        }
    }

    return null;
}

/// Does the actual work of initializing T from flags.
fn initFromParsed(comptime T: type, allocator: Allocator, flags: []Arg) !T {
    comptime {
        std.debug.assert(@hasField(T, "allocator"));
        std.debug.assert(@hasDecl(T, "deinit"));
    }

    var result = T{
        .allocator = allocator,
    };
    errdefer result.deinit();

    const this = @TypeOf(result);
    const info = @typeInfo(this);

    if ((info.Struct.fields.len -| 1) == 0) {
        return result;
    }

    inline for (info.Struct.fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "allocator")) {
            continue; // skip allocator
        }

        const fie = &@field(result, field.name);
        const extra = fie.*.extra;

        switch (extra) {
            .Flag => |f| {
                if (!(f.takesValue or f.toggle)) {
                    std.debug.print("error: invalid flag `{s}`: is not a toggle and doesn't take a value\n", .{f.name});
                    return error.InvalidFlag;
                }

                const maybe_flag = find(flags, f.name, f.short);

                if (maybe_flag) |flag| {
                    flag.setConsumed();
                    if (f.toggle) {
                        if (@TypeOf(fie.*.value) == bool) {
                            fie.*.value = true;
                            comptime continue;
                        } else {
                            std.debug.print("error: invalid switch {s}: expected bool, found {s}\n", .{
                                f.name,
                                @typeName(@TypeOf(fie.*.value)),
                            });
                            return error.InvalidSwitch;
                        }
                    }

                    if (f.takesValue) {
                        if (flag.*.Flag.value) |value| {
                            if (@TypeOf(fie.*.value) == []const u8) {
                                fie.*.value = try result.allocator.dupe(u8, value);
                                comptime continue;
                            } else {
                                if (fie.*.parse) |parse_fn| {
                                    fie.*.value = try parse_fn(value);
                                    comptime continue;
                                } else {
                                    std.debug.print("error: flag `{s}` expected a value, but no parser was provided\n", .{f.name});
                                    return error.NoValueForFlag;
                                }

                                unreachable;
                            }
                        } else {
                            std.debug.print("error: flag `{s}` expected a value, but none was provided\n", .{f.name});
                            return error.NoValueForFlag;
                        }
                    }

                    std.debug.print("error: invalid flag `{s}`: is not a toggle and doesn't take a value\n", .{f.name});
                    return error.InvalidFlag;
                } else {
                    std.debug.print("error: invalid flag `{s}`: could not find flag\n", .{f.name});
                    return error.InvalidFlag;
                }
            },
            .Remainder => {
                var not_consumed = std.ArrayList([]const u8).init(result.allocator);
                errdefer not_consumed.deinit();

                for (flags) |*flag| {
                    if (flag.isConsumed()) continue;

                    switch (flag.*) {
                        .Flag => |f| {
                            std.debug.print("TODO: figure out what to do with remainder flag {s} (value: {?s})\n", .{
                                f.name,
                                f.value,
                            });
                        },
                        .Positional => |p| {
                            flag.setConsumed();
                            try not_consumed.append(try result.allocator.dupe(u8, p.value));
                        },
                    }
                }

                if (@TypeOf(fie.*.value) == std.ArrayList([]const u8)) {
                    fie.*.value = not_consumed;
                } else {
                    std.debug.print("error: invalid remainder {s}: expected `std.ArrayList([] const u8)`, got `{s}`\n", .{
                        field.name,
                        @typeName(@TypeOf(fie.*.value)),
                    });
                    return error.InvalidRemainder;
                }
            },
            .Positional => {
                const next = nextPositional(flags);

                if (next) |flag| {
                    flag.setConsumed();
                    if (@TypeOf(fie.*.value) == []const u8) {
                        fie.*.value = try result.allocator.dupe(u8, flag.*.Positional.value);
                    } else if (fie.*.parse) |parse_fn| {
                        fie.*.value = parse_fn(flag.*.Positional.value) catch |err| {
                            std.debug.print("error: could not parse positional argument for {s}: {s}\n", .{
                                field.name,
                                @errorName(err),
                            });
                            std.debug.print("- tried to parse: {s}\n", .{flag.*.Positional.value});
                            std.debug.print("- expected type: {s}\n", .{@typeName(@TypeOf(fie.*.value))});
                            return error.InvalidPositional;
                        };
                    } else {
                        std.debug.print("error: could not parse positional argument for {s}\n", .{field.name});
                        return error.InvalidPositional;
                    }
                } else {
                    std.debug.print("error: could not find positional argument for {s}\n", .{field.name});
                    return error.NoArgumentFound;
                }
            },
        }
    }

    return result;
}

const t = std.testing;

test "parse args" {
    const args = try t.allocator.alloc([]const u8, 4);
    defer t.allocator.free(args);

    const Demo = struct {
        allocator: Allocator,

        flag: Marker([]const u8) = .{
            .value = undefined,
            .extra = Extra{
                .Flag = .{
                    .name = "flag",
                    .takesValue = true,
                },
            },
        },
        toggle: Marker(bool) = .{
            .value = undefined,
            .extra = Extra{
                .Flag = .{
                    .name = "toggle",
                    .toggle = true,
                    .takesValue = false,
                },
            },
        },
        positional: Marker([]const u8) = .{
            .value = undefined,
            .extra = Extra{
                .Positional = {},
            },
        },

        fn deinit(self: *@This()) void {
            self.allocator.free(self.flag.value);
            self.allocator.free(self.positional.value);

            self.* = undefined;
        }
    };

    args[0] = "";
    args[1] = "--flag=value";
    args[2] = "--toggle";
    args[3] = "positional";

    var result = try parseArgsImpl(Demo, t.allocator, args);
    defer result.deinit();

    try t.expectEqualStrings("value", result.flag.value);
    try t.expect(result.toggle.value);
    try t.expectEqualStrings("positional", result.positional.value);
}

test "parse fn (positional)" {
    const args = try t.allocator.alloc([]const u8, 4);
    defer t.allocator.free(args);

    args[1] = "1234";
    args[2] = "true";
    args[3] = "Value";

    const DemoEnum = enum(u8) {
        NotValue,
        Value,
    };

    const Demo = struct {
        allocator: Allocator,

        flag: Marker(u16) = .{
            .value = undefined,
            .extra = Extra{
                .Positional = {},
            },
            .parse = parsers.num(u16),
        },

        boolean: Marker(bool) = .{
            .value = undefined,
            .extra = Extra{
                .Positional = {},
            },
            .parse = parsers.boolean,
        },

        enumeration: Marker(DemoEnum) = .{
            .value = undefined,
            .extra = Extra{
                .Positional = {},
            },
            .parse = parsers.enumLiteral(DemoEnum),
        },

        fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };

    var result = try parseArgsImpl(Demo, t.allocator, args);
    defer result.deinit();

    try t.expectEqual(1234, result.flag.value);
    try t.expect(result.boolean.value);
    try t.expectEqual(DemoEnum.Value, result.enumeration.value);
}

test "parse fn (flag)" {
    const args = try t.allocator.alloc([]const u8, 4);
    defer t.allocator.free(args);

    args[1] = "--number=1234";
    args[2] = "--boolean=yes";
    args[3] = "--enumeration=Value";

    const DemoEnum = enum(u8) {
        NotValue,
        Value,
    };

    const Demo = struct {
        allocator: Allocator,

        number: Marker(u16) = .{
            .value = undefined,
            .extra = Extra{
                .Flag = .{
                    .name = "number",
                    .takesValue = true,
                },
            },
            .parse = parsers.num(u16),
        },

        boolean: Marker(bool) = .{
            .value = undefined,
            .extra = Extra{
                .Flag = .{
                    .name = "boolean",
                    .takesValue = true,
                },
            },
            .parse = parsers.boolean,
        },

        enumeration: Marker(DemoEnum) = .{
            .value = undefined,
            .extra = Extra{
                .Flag = .{
                    .name = "enumeration",
                    .takesValue = true,
                },
            },
            .parse = parsers.enumLiteral(DemoEnum),
        },

        fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };

    var result = try parseArgsImpl(Demo, t.allocator, args);
    defer result.deinit();

    try t.expectEqual(1234, result.number.value);
    try t.expect(result.boolean.value);
    try t.expectEqual(DemoEnum.Value, result.enumeration.value);
}

test "parse failure because no args" {
    const args = try t.allocator.alloc([]const u8, 1);
    defer t.allocator.free(args);

    const Demo = struct {
        allocator: Allocator,

        fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };

    args[0] = "zither";

    const result = parseArgsImpl(Demo, t.allocator, args);

    try t.expectError(error.NoArguments, result);
}
