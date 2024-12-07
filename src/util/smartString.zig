const std = @import("std");

pub const SmartString = struct {
    data: []const u8,
    kind: AllocKind,

    pub fn alloc(value: []const u8, allocator: std.mem.Allocator) !SmartString {
        return .{
            .data = try allocator.dupe(u8, value),
            .kind = .{ .Allocated = allocator },
        };
    }

    pub fn constant(comptime value: []const u8) SmartString {
        return .{
            .data = value,
            .kind = .{ .Constant = {} },
        };
    }

    /// See also: `cloneAlloc`
    pub fn clone(self: SmartString) !SmartString {
        if (!self.kind.isAllocated())
            return error.NotAllocated; // should use `cloneAlloc` instead

        return try SmartString.alloc(self.data, self.kind.Allocated);
    }

    /// Clones the string to a new allocator.
    pub fn cloneAlloc(self: SmartString, allocator: std.mem.Allocator) !SmartString {
        return try SmartString.alloc(self.data, allocator);
    }

    pub fn deinit(self: *SmartString) void {
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

            .Dead => {
                if (std.debug.runtime_safety) {
                    std.debug.panic("Double free of SmartString", .{});
                }
            },
        }
    }
};

pub const AllocKind = union(enum) {
    Constant: void,
    Allocated: std.mem.Allocator,
    Dead: void,

    inline fn isDead(self: AllocKind) bool {
        return switch (self) {
            .Dead => true,
            else => false,
        };
    }

    inline fn isAllocated(self: AllocKind) bool {
        return switch (self) {
            .Allocated => true,
            else => false,
        };
    }

    inline fn isConstant(self: AllocKind) bool {
        return switch (self) {
            .Constant => true,
            else => false,
        };
    }

    fn eql(self: AllocKind, other: AllocKind) bool {
        if (@as(std.meta.Tag(AllocKind), self) != @as(std.meta.Tag(AllocKind), other))
            return false;

        return switch (self) {
            .Allocated => |a| a.ptr == other.Allocated.ptr,
            else => true,
        };
    }
};

const t = std.testing;

test "the different kinds work" {
    const a = t.allocator;

    var strOne = try SmartString.alloc("hello, world", a);
    defer strOne.deinit();

    try t.expectEqualStrings("hello, world", strOne.data);
    try t.expectEqual(AllocKind{ .Allocated = a }, strOne.kind);

    var strTwo = SmartString.constant("hello, world");
    defer strTwo.deinit();

    try t.expectEqualStrings("hello, world", strTwo.data);
    try t.expectEqual(AllocKind{ .Constant = {} }, strTwo.kind);

    try t.expectEqualStrings(strOne.data, strTwo.data);
    try t.expect(!strOne.kind.eql(strTwo.kind));
}

test "allocKind eql works" {
    const a = AllocKind{ .Dead = {} };
    const b = AllocKind{ .Constant = {} };

    try t.expect(!a.eql(b));
    try t.expect(!b.eql(a));

    const c = AllocKind{ .Allocated = t.allocator };
    const d = AllocKind{ .Allocated = t.allocator };

    try t.expect(c.eql(d));
    try t.expect(!d.eql(a));
    try t.expect(!d.eql(b));
}

test "clone works" {
    const a = t.allocator;

    var strOne = try SmartString.alloc("hello, world", a);
    defer strOne.deinit();

    var strTwo = try strOne.clone();
    defer strTwo.deinit();

    try t.expectEqualStrings("hello, world", strOne.data);
    try t.expectEqualStrings("hello, world", strTwo.data);

    try t.expect(strOne.kind.eql(strTwo.kind));
}
