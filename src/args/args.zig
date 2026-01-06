const std = @import("std");

const builtin = @import("builtin");

const DEBUG_MODE = builtin.mode == .Debug;

const Allocator = std.mem.Allocator;

pub const parsers = @import("./parsers/parsers.zig");

const Arg = @import("./arg.zig").Arg;
const niceTypeName = @import("../util/utils.zig").niceTypeName;

const log = std.log.scoped(.args);

/// Metadata for a field that is parseable by the argument parser.
pub const Extra = union(enum(u2)) {
    Positional: struct {
        about: ?[]const u8 = null,
        type_hint: ?[]const u8 = null,
    },
    Remainder,
    Flag: struct {
        name: []const u8,
        short: ?[]const u8 = null,
        about: ?[]const u8 = null,
        type_hint: ?[]const u8 = null,
        toggle: bool = false,
        takes_value: bool = false,
        /// Ensures that if the flag is present, the parser will not continue parsing.
        ///
        /// Warning: this is a dangerous option, as all subsequent fields will be ignored even if they have values.
        /// Only use this for flags like `--help` or `--version` or similar.
        short_circuit: bool = false,
    },
};

/// A marker for any field `T` that you want to be parseable by the argument parser.
pub fn Marker(comptime T: type) type {
    return struct {
        value: T = undefined,
        extra: Extra,
        /// Optional function that parses the value of the field.
        /// If this is null, no parsing will take place.
        ///
        /// This function can be any function that takes a `[]const u8` and returns `anyerror!T`.
        ///
        /// However, it is recommended to use `lys.args.parsers` for common types.
        parse: ?parsers.ParseSignature(T) = null,
    };
}

pub const help = @import("./help.zig");

/// <https://git.cutie.zone/lyssieth/zither/issues/1>
///
/// Parsing order of arguments is based on the order they are declared in `T`.
pub fn parseArgs(comptime T: type, allocator: Allocator) !T {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    return parseArgsFromSlice(T, allocator, args[1..]);
}

/// All items of `args` must be valid, otherwise you will get a General Protection Fault.
/// Do not pass the process name as an argument.
///
/// Parsing order of arguments is based on the order they are declared in `T`.
pub fn parseArgsFromSlice(comptime T: type, allocator: Allocator, args: [][]const u8) !T {
    var flags = try std.ArrayList(Arg).initCapacity(allocator, 4);
    defer flags.deinit(allocator);

    if (args.len == 0) {
        return error.NoArguments;
    }

    for (args) |arg| {
        if (arg.len == 0) continue; // skip empty args
        if (@intFromPtr(arg.ptr) == 0xaaaaaaaaaaaaaaaa) return error.UninitializedArgument;

        const argument = try Arg.parseArg(arg);

        try flags.append(allocator, argument);
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
        if (!@hasField(T, "allocator"))
            @compileError("T must have an allocator");
        if (!@hasDecl(T, "deinit"))
            @compileError("T must have a deinit function");
    }

    var result = T{
        .allocator = allocator,
    };
    errdefer result.deinit();

    const this = @TypeOf(result);
    const info = @typeInfo(this);

    if ((info.@"struct".fields.len -| 1) == 0) {
        return result;
    }

    inline for (info.@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "allocator")) {
            continue; // skip allocator
        }

        const fie = &@field(result, field.name);
        const field_type = @typeInfo(@TypeOf(fie.*.value));
        const extra: Extra = fie.*.extra;

        switch (extra) {
            .Flag => |f| {
                if (!(f.takes_value or f.toggle)) {
                    log.err("flag `{s}` must be a toggle or take a value, but it was neither", .{f.name});
                    unreachable;
                }

                const maybe_flag = find(flags, f.name, f.short);

                if (maybe_flag) |flag| {
                    flag.setConsumed();
                    if (f.toggle) {
                        if (@TypeOf(fie.*.value) == bool) {
                            fie.*.value = true;

                            if (f.short_circuit) {
                                return result;
                            }
                            comptime continue;
                        } else {
                            log.err("invalid toggle `{s}`: expected T == bool, found: {s}", .{
                                f.name,
                                niceTypeName(@TypeOf(fie.*.value)),
                            });
                            return error.InvalidToggle;
                        }
                    }

                    if (f.takes_value) {
                        if (flag.*.Flag.value) |value| {
                            if (@TypeOf(fie.*.value) == []const u8) {
                                fie.*.value = try result.allocator.dupe(u8, value);

                                if (f.short_circuit) {
                                    return result;
                                }
                                comptime continue;
                            } else {
                                if (fie.*.parse) |parse_fn| {
                                    fie.*.value = parse_fn(value) catch |err| {
                                        log.err("could not parse flag `{s}`: `{s}`", .{
                                            field.name,
                                            @errorName(err),
                                        });
                                        log.err("- tried to parse: {s}", .{value});
                                        log.err("- expected type: {s}", .{niceTypeName(@TypeOf(fie.*.value))});
                                        return error.InvalidFlag;
                                    };

                                    if (f.short_circuit) {
                                        return result;
                                    }
                                    comptime continue;
                                } else {
                                    log.err("flag `{s}` expected a value, but no parser was provided for type `{s}`", .{
                                        f.name,
                                        niceTypeName(@TypeOf(fie.*.value)),
                                    });
                                    return error.NoValueForFlag;
                                }
                            }
                        } else {
                            log.err("flag `{s}` expected a value, but none was provided", .{f.name});
                            return error.NoValueForFlag;
                        }
                    }

                    log.err("invalid flag `{s}`: is not a toggle and doesn't take a value", .{f.name});
                    return error.InvalidFlag;
                }

                switch (field_type) {
                    .optional => |_| {
                        log.debug("flag `{s}` is optional, and we couldn't find a value for it, so leaving as default value", .{f.name});
                        comptime continue;
                    },

                    else => {
                        if (f.toggle) {
                            if (@TypeOf(fie.*.value) == bool) {
                                fie.*.value = false;
                                comptime continue;
                            } else {
                                log.err("invalid toggle `{s}`: expected T == bool, found: {s}", .{
                                    f.name,
                                    niceTypeName(@TypeOf(fie.*.value)),
                                });
                                return error.InvalidToggle;
                            }
                        }

                        if (builtin.is_test) {
                            // early return to not pollute the stderr
                            return error.NoValueForFlag;
                        }

                        if (DEBUG_MODE) {
                            log.warn("flag `{s}` expected a value, but none was provided", .{f.name});
                            log.warn("expected type: {s}", .{niceTypeName(@TypeOf(fie.*.value))});
                        } else {
                            log.err("flag `{s}` is required (expected type `{s}`)", .{
                                f.name,
                                niceTypeName(@TypeOf(fie.*.value)),
                            });
                        }

                        log.warn("hint: try `--{s}=<value>`", .{f.name});
                        if (f.short) |short| {
                            log.warn("hint: try `-{s}=<value>`", .{short});
                        }

                        return error.NoValueForFlag;
                    },
                }

                log.err("invalid flag `{s}`: could not be located in args", .{f.name});
                return error.CouldNotFindFlag;
            },
            .Remainder => {
                var not_consumed = try std.ArrayList([]const u8).initCapacity(result.allocator, 8);
                errdefer not_consumed.deinit(result.allocator);

                for (flags) |*flag| {
                    if (flag.isConsumed()) continue;

                    switch (flag.*) {
                        .Flag => |f| {
                            flag.setConsumed();
                            const flagText = blk: {
                                if (f.value) |value| {
                                    break :blk try std.fmt.allocPrint(result.allocator, "{s}={s}", .{
                                        f.name,
                                        value,
                                    });
                                } else {
                                    break :blk try result.allocator.dupe(u8, f.name);
                                }
                            };
                            defer result.allocator.free(flagText);

                            if (f.short) {
                                try not_consumed.append(result.allocator, try std.fmt.allocPrint(result.allocator, "-{s}", .{flagText}));
                            } else {
                                try not_consumed.append(result.allocator, try std.fmt.allocPrint(result.allocator, "--{s}", .{flagText}));
                            }
                        },
                        .Positional => |p| {
                            flag.setConsumed();
                            try not_consumed.append(result.allocator, try result.allocator.dupe(u8, p.value));
                        },
                    }
                }

                if (@TypeOf(fie.*.value) == std.ArrayList([]const u8)) {
                    fie.*.value = not_consumed;
                } else {
                    log.err("invalid remainder field `{s}`: expected T == `std.ArrayList([] const u8)`, got T == `{s}`", .{
                        field.name,
                        niceTypeName(@TypeOf(fie.*.value)),
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
                            log.err("could not parse positional argument for `{s}`: `{s}`", .{
                                field.name,
                                @errorName(err),
                            });
                            log.err("- tried to parse: {s}", .{flag.*.Positional.value});
                            log.err("- expected type: {s}", .{niceTypeName(@TypeOf(fie.*.value))});
                            return error.InvalidPositional;
                        };
                    } else {
                        log.err("could not parse positional argument for `{s}`: no parser provided", .{field.name});
                        return error.InvalidPositional;
                    }
                } else {
                    switch (field_type) {
                        .optional => {
                            if (!builtin.is_test) {
                                log.warn("could not find positional argument for `{s}`, using default value", .{field.name});
                            }
                            comptime continue;
                        },

                        else => {},
                    }

                    if (builtin.is_test) {
                        // early return to not pollute the stderr
                        return error.NoArgumentFound;
                    }

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
            .extra = Extra{
                .Flag = .{
                    .name = "flag",
                    .takes_value = true,
                },
            },
        },
        toggle: Marker(bool) = .{
            .extra = Extra{
                .Flag = .{
                    .name = "toggle",
                    .toggle = true,
                },
            },
        },
        positional: Marker([]const u8) = .{
            .extra = Extra{
                .Positional = .{},
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

    var result = try parseArgsFromSlice(Demo, t.allocator, args);
    defer result.deinit();

    try t.expectEqualStrings("value", result.flag.value);
    try t.expect(result.toggle.value);
    try t.expectEqualStrings("positional", result.positional.value);
}

test "missing flag" {
    const args = try t.allocator.alloc([]const u8, 1);
    defer t.allocator.free(args);

    args[0] = "1234";

    const Demo = struct {
        allocator: Allocator,

        flag: Marker(bool) = .{
            .extra = Extra{
                .Flag = .{
                    .name = "flag",
                    .takes_value = true,
                },
            },
            .parse = parsers.boolean,
        },

        fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };

    const result = parseArgsFromSlice(Demo, t.allocator, args);
    try t.expectError(error.NoValueForFlag, result);
}

test "missing toggle" {
    const args = try t.allocator.alloc([]const u8, 1);
    defer t.allocator.free(args);

    args[0] = "1234";

    const Demo = struct {
        allocator: Allocator,

        flag: Marker(bool) = .{
            .extra = Extra{
                .Flag = .{
                    .name = "flag",
                    .toggle = true,
                },
            },
        },

        fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };

    const result = try parseArgsFromSlice(Demo, t.allocator, args);

    try t.expect(result.flag.value == false);
}

test "missing positional because no args" {
    const args = try t.allocator.alloc([]const u8, 0);
    defer t.allocator.free(args);

    const Demo = struct {
        allocator: Allocator,

        positional: Marker([]const u8) = .{
            .extra = Extra{
                .Positional = .{},
            },
        },

        fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };

    const result = parseArgsFromSlice(Demo, t.allocator, args);
    try t.expectError(error.NoArguments, result);
}

test "missing positional because empty arg" {
    const args = try t.allocator.alloc([]const u8, 1);
    defer t.allocator.free(args);

    args[0] = "";

    const Demo = struct {
        allocator: Allocator,

        positional: Marker([]const u8) = .{
            .extra = Extra{
                .Positional = .{},
            },
        },

        fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };

    const result = parseArgsFromSlice(Demo, t.allocator, args);
    try t.expectError(error.NoArgumentFound, result);
}

test "positional has default value so we get a free pass" {
    const args = try t.allocator.alloc([]const u8, 1);
    defer t.allocator.free(args);

    args[0] = "--toggle";

    const Demo = struct {
        allocator: Allocator,

        positional: Marker(?u8) = .{
            .value = 255,
            .extra = .{
                .Positional = .{},
            },
            .parse = parsers.num_nullable(u8),
        },

        fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };

    const result = try parseArgsFromSlice(Demo, t.allocator, args);

    try t.expectEqual(255, result.positional.value);
}

test "parse fn (positional)" {
    const args = try t.allocator.alloc([]const u8, 3);
    defer t.allocator.free(args);

    args[0] = "1234";
    args[1] = "true";
    args[2] = "Value";

    const DemoEnum = enum(u8) {
        NotValue,
        Value,
    };

    const Demo = struct {
        allocator: Allocator,

        flag: Marker(u16) = .{
            .extra = Extra{
                .Positional = .{},
            },
            .parse = parsers.num(u16),
        },

        boolean: Marker(bool) = .{
            .extra = Extra{
                .Positional = .{},
            },
            .parse = parsers.boolean,
        },

        enumeration: Marker(DemoEnum) = .{
            .extra = Extra{
                .Positional = .{},
            },
            .parse = parsers.enum_literal(DemoEnum),
        },

        fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };

    var result = try parseArgsFromSlice(Demo, t.allocator, args);
    defer result.deinit();

    try t.expectEqual(1234, result.flag.value);
    try t.expect(result.boolean.value);
    try t.expectEqual(DemoEnum.Value, result.enumeration.value);
}

test "parse fn (flag)" {
    const args = try t.allocator.alloc([]const u8, 3);
    defer t.allocator.free(args);

    args[0] = "--number=1234";
    args[1] = "--boolean=yes";
    args[2] = "--enumeration=Value";

    const DemoEnum = enum(u8) {
        NotValue,
        Value,
    };

    const Demo = struct {
        allocator: Allocator,

        number: Marker(u16) = .{
            .extra = Extra{
                .Flag = .{
                    .name = "number",
                    .takes_value = true,
                },
            },
            .parse = parsers.num(u16),
        },

        boolean: Marker(bool) = .{
            .extra = Extra{
                .Flag = .{
                    .name = "boolean",
                    .toggle = true,
                },
            },
            .parse = parsers.boolean,
        },

        enumeration: Marker(DemoEnum) = .{
            .extra = Extra{
                .Flag = .{
                    .name = "enumeration",
                    .takes_value = true,
                },
            },
            .parse = parsers.enum_literal(DemoEnum),
        },

        fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };

    var result = try parseArgsFromSlice(Demo, t.allocator, args);
    defer result.deinit();

    try t.expectEqual(1234, result.number.value);
    try t.expect(result.boolean.value);
    try t.expectEqual(DemoEnum.Value, result.enumeration.value);
}

test "parse failure because no args" {
    const args = try t.allocator.alloc([]const u8, 0);
    defer t.allocator.free(args);

    const Demo = struct {
        allocator: Allocator,

        fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };

    const result = parseArgsFromSlice(Demo, t.allocator, args);

    try t.expectError(error.NoArguments, result);
}

test "remainder has value" {
    const args = try t.allocator.alloc([]const u8, 3);
    defer t.allocator.free(args);

    args[0] = "--flag=value";
    args[1] = "--toggle";
    args[2] = "positional";

    const Demo = struct {
        allocator: Allocator,

        remainder: Marker(std.ArrayList([]const u8)) = .{
            .extra = .{ .Remainder = {} },
        },

        fn deinit(self: *@This()) void {
            for (self.remainder.value.items) |item| {
                self.allocator.free(item);
            }
            self.remainder.value.deinit(self.allocator);

            self.* = undefined;
        }
    };

    var result = try parseArgsFromSlice(Demo, t.allocator, args);
    defer result.deinit();

    try t.expectEqual(3, result.remainder.value.items.len);

    try t.expectEqualStrings("--flag=value", result.remainder.value.items[0]);
}

test "sub command from remainder" {
    const args = try t.allocator.alloc([]const u8, 3);
    defer t.allocator.free(args);

    args[0] = "--flag=value";
    args[1] = "command";
    args[2] = "--toggle";

    const DemoOuter = struct {
        allocator: Allocator,

        positional: Marker([]const u8) = .{
            .extra = .{ .Positional = .{} },
        },
        remainder: Marker(std.ArrayList([]const u8)) = .{
            .extra = .{ .Remainder = {} },
        },

        fn deinit(self: *@This()) void {
            self.allocator.free(self.positional.value);

            for (self.remainder.value.items) |item| {
                self.allocator.free(item);
            }
            self.remainder.value.deinit(self.allocator);

            self.* = undefined;
        }
    };

    var outerResult = try parseArgsFromSlice(DemoOuter, t.allocator, args);
    defer outerResult.deinit();

    try t.expectEqualStrings("command", outerResult.positional.value);
    try t.expectEqual(2, outerResult.remainder.value.items.len);

    try t.expectEqualStrings("--flag=value", outerResult.remainder.value.items[0]);
    try t.expectEqualStrings("--toggle", outerResult.remainder.value.items[1]);

    const DemoInner = struct {
        allocator: Allocator,

        flag: Marker([]const u8) = .{
            .extra = .{
                .Flag = .{
                    .name = "flag",
                    .takes_value = true,
                },
            },
        },
        toggle: Marker(bool) = .{
            .extra = Extra{
                .Flag = .{
                    .name = "toggle",
                    .toggle = true,
                },
            },
        },

        fn deinit(self: *@This()) void {
            self.allocator.free(self.flag.value);
            self.* = undefined;
        }
    };

    var innerResult = try parseArgsFromSlice(DemoInner, t.allocator, outerResult.remainder.value.items);
    defer innerResult.deinit();

    try t.expectEqualStrings("value", innerResult.flag.value);
    try t.expect(innerResult.toggle.value);
}
