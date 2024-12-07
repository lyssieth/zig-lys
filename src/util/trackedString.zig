const std = @import("std");

pub const TrackedString = struct {
    data: []const u8,
    kind: AllocKind,

    pub fn alloc(value: []const u8, allocator: std.mem.Allocator) !TrackedString {
        return .{
            .data = try allocator.dupe(u8, value),
            .kind = .{ .Allocated = allocator },
        };
    }

    pub fn constant(comptime value: []const u8) TrackedString {
        return .{
            .data = value,
            .kind = .{ .Constant = {} },
        };
    }

    pub fn deinit(self: *TrackedString) void {
        switch (self.*.kind) {
            .Constant => {
                self.*.data = undefined;
                self.*.kind = .{ .Dead = {} };
            },

            .Allocated => |allocator| {
                allocator.free(self.data);
                self.*.data = undefined;
                self.*.kind = .{ .Dead = {} };
            },

            .Dead => {},
        }
    }
};

pub const AllocKind = union(enum) {
    Constant: void,
    Allocated: std.mem.Allocator,
    Dead: void,

    fn eql(self: AllocKind, other: AllocKind) bool {
        return switch (self) {
            .Constant => switch (other) {
                .Constant => true,
                else => false,
            },
            .Allocated => |a| switch (other) {
                .Allocated => |b| std.meta.eql(a, b),
                else => false,
            },
            .Dead => switch (other) {
                .Dead => true,
                else => false,
            },
        };
    }
};

const t = std.testing;

test "the different kinds work" {
    const a = t.allocator;

    var strOne = try TrackedString.alloc("hello, world", a);
    defer strOne.deinit();

    try t.expectEqualStrings("hello, world", strOne.data);
    try t.expectEqual(AllocKind{ .Allocated = a }, strOne.kind);

    var strTwo = TrackedString.constant("hello, world");
    defer strTwo.deinit();

    try t.expectEqualStrings("hello, world", strTwo.data);
    try t.expectEqual(AllocKind{ .Constant = {} }, strTwo.kind);

    try t.expectEqualStrings(strOne.data, strTwo.data);
    try t.expect(!strOne.kind.eql(strTwo.kind));
}
