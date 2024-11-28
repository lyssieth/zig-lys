const std = @import("std");

const log = std.log.scoped(.help);

const argLib = @import("args.zig");
const Marker = argLib.Marker;
const Extra = argLib.Extra;

const niceTypeName = @import("utils.zig").niceTypeName;

pub fn printHelp(comptime T: type, comptime name: []const u8, writer: std.io.AnyWriter) !void {
    const info = @typeInfo(T);

    switch (info) {
        .Struct => {},
        else => {
            log.warn("We only support printing the help of `Struct`s, not {s}", .{@tagName(info)});
            return error.NotImplemented;
        },
    }

    var hasFlags = false;
    inline for (info.Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, "allocator")) {
            comptime continue;
        }

        if (field.type == Marker(bool)) {
            hasFlags = true;
            comptime break;
        }
    }

    var hasPositionals = false;
    inline for (info.Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, "allocator")) {
            comptime continue;
        }

        const valueOpaque = field.default_value orelse @panic("Missing default value for field " ++ field.name);
        const valueMarker: *const field.type = @alignCast(@ptrCast(valueOpaque));
        const value: Extra = @field(valueMarker, "extra");

        switch (value) {
            .Positional => {
                hasPositionals = true;
                comptime break;
            },
            else => {},
        }
    }

    var hasRemainder = false;
    inline for (info.Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, "allocator")) {
            comptime continue;
        }

        const valueOpaque = field.default_value orelse @panic("Missing default value for field " ++ field.name);
        const valueMarker: *const field.type = @alignCast(@ptrCast(valueOpaque));
        const value: Extra = @field(valueMarker, "extra");

        switch (value) {
            .Remainder => {
                hasRemainder = true;
                comptime break;
            },
            else => {},
        }
    }

    try writer.print("Usage: {s}", .{name});

    if (hasFlags) {
        try writer.print(" [flags]", .{});
    }

    if (hasPositionals) {
        inline for (info.Struct.fields) |field| {
            if (std.mem.eql(u8, field.name, "allocator")) {
                comptime continue;
            }

            const valueOpaque = field.default_value orelse @panic("Missing default value for field " ++ field.name);
            const valueMarker: *const field.type = @alignCast(@ptrCast(valueOpaque));
            const value: Extra = @field(valueMarker, "extra");

            switch (value) {
                .Positional => {
                    try writer.print(" <{s}>", .{field.name});
                },
                else => {},
            }
        }
    }

    if (hasRemainder) {
        try writer.print(" [...]", .{});
    }

    try writer.print("\n", .{});
    try writer.print("Legend: <required> [optional]\n\n", .{});

    inline for (info.Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, "allocator")) {
            comptime continue;
        }

        const valueOpaque = field.default_value orelse @panic("Missing default value for field " ++ field.name);
        const valueMarker: *const field.type = @alignCast(@ptrCast(valueOpaque));
        const valueType = niceTypeName(@TypeOf(valueMarker.*.value));

        const isOptional = std.mem.startsWith(u8, valueType, "?");

        switch (valueMarker.*.extra) {
            .Remainder => {
                comptime continue;
            },
            .Positional => |pos| {
                try writer.print("* <{s}>: {s}", .{
                    field.name,
                    valueType,
                });

                if (pos.typeHint) |typeHint| {
                    try writer.print(" ({s})", .{typeHint});
                }

                if (pos.about) |about| {
                    try writer.print(" | {s}", .{about});
                }
            },
            .Flag => |flag| {
                try writer.print("* ", .{});

                try writer.print("--{s}", .{
                    flag.name,
                });

                if (flag.takesValue) {
                    try writer.print("=<value>", .{});
                }

                if (flag.short) |short| {
                    try writer.print(" (-{s}", .{short});

                    if (flag.takesValue) {
                        try writer.print("=<value>", .{});
                    }

                    try writer.print(")", .{});
                }

                if (flag.takesValue) {
                    try writer.print(": {s}", .{valueType});

                    if (flag.typeHint) |typeHint| {
                        try writer.print(" ({s})", .{typeHint});
                    }
                }

                if (!isOptional and !flag.toggle) {
                    try writer.print(" <required>", .{});
                }

                if (flag.about) |about| {
                    try writer.print(" | {s}", .{about});
                }
            },
        }

        try writer.print("\n", .{});
    }
}

const t = std.testing;
test "empty help" {
    var buf = std.ArrayList(u8).init(t.allocator);
    defer buf.deinit();

    const Demo = struct {};

    try printHelp(Demo, "demo", buf.writer().any());

    try t.expectEqualStrings(
        \\Usage: demo
        \\Legend: <required> [optional]
        \\
        \\
    , buf.items);
}

test "basic help" {
    var buf = std.ArrayList(u8).init(t.allocator);
    defer buf.deinit();

    const Demo = struct {
        verbose: Marker(bool) = .{
            .value = undefined,
            .extra = .{
                .Flag = .{
                    .name = "verbose",
                    .short = "v",

                    .toggle = true,
                },
            },
        },
        positional: Marker([]const u8) = .{
            .value = undefined,
            .extra = .{ .Positional = .{} },
        },

        remainder: Marker(std.ArrayList([]const u8)) = .{
            .value = undefined,
            .extra = .{ .Remainder = {} },
        },
    };

    try printHelp(Demo, "demo", buf.writer().any());

    try t.expectEqualStrings(
        \\Usage: demo [flags] <positional> [...]
        \\Legend: <required> [optional]
        \\
        \\* --verbose (-v)
        \\* <positional>: string
        \\
    , buf.items);
}

test "about and type hint" {
    var buf = std.ArrayList(u8).init(t.allocator);
    defer buf.deinit();

    const Demo = struct {
        verbose: Marker(bool) = .{
            .value = undefined,
            .extra = .{ .Flag = .{
                .name = "verbose",
                .short = "v",
                .takesValue = true,

                .about = "makes the output verbose",
                .typeHint = "yes/no",
            } },
        },
    };

    try printHelp(Demo, "demo", buf.writer().any());

    try t.expectEqualStrings(
        \\Usage: demo [flags]
        \\Legend: <required> [optional]
        \\
        \\* --verbose=<value> (-v=<value>): bool (yes/no) <required> | makes the output verbose
        \\
    , buf.items);
}
