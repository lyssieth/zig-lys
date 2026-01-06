const std = @import("std");

const log = std.log.scoped(.help);

const arg_lib = @import("args.zig");
const Marker = arg_lib.Marker;
const Extra = arg_lib.Extra;

const niceTypeName = @import("../util/utils.zig").niceTypeName;

pub fn printHelp(comptime T: type, comptime name: []const u8, writer: *std.Io.Writer) !void {
    const info = @typeInfo(T);

    switch (info) {
        .@"struct" => {},
        else => {
            log.warn("We only support printing the help of structs, not {s}", .{@tagName(info)});
            return error.NotImplemented;
        },
    }

    var hasFlags = false;
    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "allocator")) {
            comptime continue;
        }

        if (field.type == Marker(bool)) {
            hasFlags = true;
            comptime break;
        }
    }

    var hasPositionals = false;
    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "allocator")) {
            comptime continue;
        }

        const valueOpaque = field.default_value_ptr orelse @panic("Missing default value for field " ++ field.name);
        const valueMarker: *const field.type = @ptrCast(@alignCast(valueOpaque));
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
    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "allocator")) {
            comptime continue;
        }

        const valueOpaque = field.default_value_ptr orelse @panic("Missing default value for field " ++ field.name);
        const valueMarker: *const field.type = @ptrCast(@alignCast(valueOpaque));
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
        inline for (info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, "allocator")) {
                comptime continue;
            }

            const valueOpaque = field.default_value_ptr orelse @panic("Missing default value for field " ++ field.name);
            const valueMarker: *const field.type = @ptrCast(@alignCast(valueOpaque));
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

    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "allocator")) {
            comptime continue;
        }

        const valueOpaque = field.default_value_ptr orelse @panic("Missing default value for field " ++ field.name);
        const valueMarker: *const field.type = @ptrCast(@alignCast(valueOpaque));
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

                if (pos.type_hint) |typeHint| {
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

                if (flag.takes_value) {
                    try writer.print("=<value>", .{});
                }

                if (flag.short) |short| {
                    try writer.print(" (-{s}", .{short});

                    if (flag.takes_value) {
                        try writer.print("=<value>", .{});
                    }

                    try writer.print(")", .{});
                }

                if (flag.takes_value) {
                    try writer.print(": {s}", .{valueType});

                    if (flag.type_hint) |typeHint| {
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
    const Demo = struct {};

    var buf = std.Io.Writer.Allocating.init(t.allocator);
    defer buf.deinit();

    try printHelp(Demo, "demo", &buf.writer);

    try t.expectEqualStrings(
        \\Usage: demo
        \\Legend: <required> [optional]
        \\
        \\
    , buf.written());
}

test "basic help" {
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

    var buf = std.Io.Writer.Allocating.init(t.allocator);
    defer buf.deinit();

    try printHelp(
        Demo,
        "demo",
        &buf.writer,
    );

    try t.expectEqualStrings(
        \\Usage: demo [flags] <positional> [...]
        \\Legend: <required> [optional]
        \\
        \\* --verbose (-v)
        \\* <positional>: string
        \\
    , buf.written());
}

test "about and type hint" {
    const Demo = struct {
        verbose: Marker(bool) = .{
            .value = undefined,
            .extra = .{ .Flag = .{
                .name = "verbose",
                .short = "v",
                .takes_value = true,

                .about = "makes the output verbose",
                .type_hint = "yes/no",
            } },
        },
    };

    var buf = std.Io.Writer.Allocating.init(t.allocator);
    defer buf.deinit();

    try printHelp(
        Demo,
        "demo",
        &buf.writer,
    );

    try t.expectEqualStrings(
        \\Usage: demo [flags]
        \\Legend: <required> [optional]
        \\
        \\* --verbose=<value> (-v=<value>): bool (yes/no) <required> | makes the output verbose
        \\
    , buf.written());
}
