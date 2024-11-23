const std = @import("std");

/// A function that validates a string value.
/// It should return an error if the value is unparseable.
/// Or `true` if the value is valid.
/// Or `false` if the value is invalid.
pub const ValidateSignature = *const fn (value: []const u8) anyerror!bool;

pub const string = @import("./string.zig");
pub const number = @import("./number.zig");

comptime {
    const builtin = @import("builtin");

    if (builtin.is_test) {
        std.mem.doNotOptimizeAway(string);
        std.mem.doNotOptimizeAway(number);
    }
}

const this = @This();
test "valid validator signatures" {
    const t = std.testing;

    const decls = @typeInfo(this).Struct.decls;

    inline for (decls) |decl| {
        const field = @field(this, decl.name);
        if (comptime std.mem.startsWith(u8, @typeName(field), "*")) {
            comptime continue; // skip `ValidateSignature`
        }

        inline for (@typeInfo(field).Struct.decls) |function| {
            try t.expectEqual(ValidateSignature, @TypeOf(&@field(field, function.name)));
        }
    }
}
