const std = @import("std");
const builtin = @import("builtin");

pub fn enumLiteral(comptime T: type) *const fn (value: []const u8) anyerror!T {
    const container = struct {
        fn func(value: []const u8) anyerror!T {
            return parseEnumFromStr(T, value);
        }
    };

    return &container.func;
}

const log = std.log.scoped(.args);

fn parseEnumFromStr(comptime T: type, str: []const u8) !T {
    const heapAllocator = std.heap.page_allocator;
    const lower = try std.ascii.allocLowerString(heapAllocator, str);
    defer heapAllocator.free(lower);
    const info = @typeInfo(T);

    comptime {
        if (std.meta.activeTag(info) != .@"enum") {
            @compileError("Expected enum type, got " ++ @typeName(T));
        }
    }

    inline for (info.@"enum".fields) |field| {
        const lowerFieldName = try std.ascii.allocLowerString(heapAllocator, field.name);
        defer heapAllocator.free(lowerFieldName);
        if (std.mem.eql(u8, lowerFieldName, lower)) {
            return @enumFromInt(field.value);
        }
    }

    if (builtin.is_test) {
        return error.CouldNotParse; // short circuit to prevent test output pollution
        // todo: maybe find a way to get Zig tests to run without stderr *unless* they fail?
    }

    log.err("could not parse `{s}` as enum `{s}`", .{ str, @typeName(T) });
    log.warn("hint: try one of the following:", .{});

    inline for (info.@"enum".fields) |field| {
        const lowerFieldName = try std.ascii.allocLowerString(heapAllocator, field.name);
        defer heapAllocator.free(lowerFieldName);
        log.warn("- {s}", .{lowerFieldName});
    }

    return error.CouldNotParse;
}

test "enum literal" {
    const t = std.testing;

    const Demo = enum(u8) {
        A,
        B,
    };

    try t.expectEqual(Demo.A, try parseEnumFromStr(Demo, "A"));
    try t.expectEqual(Demo.B, try parseEnumFromStr(Demo, "B"));

    try t.expectError(error.CouldNotParse, parseEnumFromStr(Demo, "DefinitelyNot"));
}
