const std = @import("std");

pub const TrackedString = struct {
    data: []const u8,
    kind: AllocKind,

    pub fn initAlloc(value: []const u8, allocator: std.mem.Allocator) !TrackedString {
        return .{
            .data = try allocator.dupe(value),
            .kind = .{ .Allocated = allocator },
        };
    }

    pub fn initConst(comptime value: []const u8) TrackedString {
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
};
