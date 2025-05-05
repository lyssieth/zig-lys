//! SmartString is a memory-aware string type that provides explicit tracking of allocation state.
//! It maintains information about whether the underlying string data is:
//! - Allocated: Owned by an allocator and must be freed
//! - Constant: Compile-time constant that requires no freeing
//! - Dead: Already freed (helps catch use-after-free in debug builds)
//!
//! This type is particularly useful in scenarios where string ownership needs to be
//! explicit, such as logging systems or string caches where mixing allocated and
//! constant strings is common.
//!
//! Example:
//! ```
//! const str1 = try SmartString.alloc("hello", allocator);
//! defer str1.deinit();
//!
//! const str2 = SmartString.constant("world");
//! defer str2.deinit(); // Safe to call deinit() even on constants
//! ```

const std = @import("std");

/// The actual string data. This becomes undefined after calling `deinit()`.
data: []const u8,
/// Tracks the allocation state of the string.
kind: AllocKind,

const SmartString = @This();

/// Creates a new SmartString by allocating and copying the input string.
///
/// The resulting string must be freed with `deinit()`.
///
/// Example:
/// ```
/// const str = try SmartString.alloc("dynamic string", allocator);
/// defer str.deinit();
/// ```
pub fn alloc(value: []const u8, allocator: std.mem.Allocator) !SmartString {
    return .{
        .data = try allocator.dupe(u8, value),
        .kind = .{ .Allocated = allocator },
    };
}

/// Creates a new SmartString from a compile-time known string.
///
/// The string data is stored in the binary and never freed. Calling `deinit()`
/// is still valid and will mark the string as Dead, including swapping out the
/// `data` field for `undefined`.
///
/// Example:
/// ```
/// const str = SmartString.constant("static string");
/// ```
pub fn constant(comptime value: []const u8) SmartString {
    return .{
        .data = value,
        .kind = .{ .Constant = {} },
    };
}

/// Creates a copy of an allocated SmartString using its original allocator.
///
/// Returns error.NotAllocated if called on a constant or dead string.
/// For those cases, use `cloneAlloc()` instead.
///
/// Example:
/// ```
/// const str1 = try SmartString.alloc("hello", allocator);
/// const str2 = try str1.clone(); // Uses same allocator as str1
/// ```
pub fn clone(self: SmartString) !SmartString {
    if (!self.kind.isAllocated())
        return error.NotAllocated; // should use `cloneAlloc` instead

    return try SmartString.alloc(self.data, self.kind.Allocated);
}

/// Creates a copy of any SmartString using the provided allocator.
///
/// This works for all SmartString variants (allocated, constant, or dead),
/// making it more flexible than `clone()`.
///
/// Example:
/// ```
/// const str1 = SmartString.constant("hello");
/// const str2 = try str1.cloneAlloc(new_allocator);
/// ```
pub fn cloneAlloc(self: SmartString, allocator: std.mem.Allocator) !SmartString {
    return try SmartString.alloc(self.data, allocator);
}

/// Compares two SmartStrings for equality.
/// Two SmartStrings are equal if they have the same contents.
///
/// It can also compare a SmartString to `[]u8` or `[]const u8`, which will
/// compare the data slices in memory.
///
/// Example:
/// ```
/// const str1 = SmartString.constant("hello");
/// const str2 = SmartString.constant("hello");
/// const str3 = SmartString.constant("world");
///
/// try t.expect(str1.eql(str2));
/// try t.expect(!str1.eql(str3));
/// ```
pub fn eql(self: SmartString, other: anytype) bool {
    if (@TypeOf(other) == []const u8) {
        return std.mem.eql(u8, self.data, other);
    } else if (@TypeOf(other) == []u8) {
        return std.mem.eql(u8, self.data, other);
    } else if (@TypeOf(other) == SmartString) {
        return std.mem.eql(u8, self.data, other.data);
    }
}

/// Frees the string if it was allocated and marks it as Dead.
///
/// Safe to call on any variant (allocated, constant, or dead).
/// Will trigger a panic in debug builds if called on an already dead string.
///
/// After calling `deinit()`:
/// - The `data` slice becomes undefined
/// - The `kind` becomes Dead
/// - The string should not be used anymore
///
/// Example:
/// ```
/// var str = try SmartString.alloc("hello", allocator);
/// str.deinit();
/// // str.data is now undefined
/// ```
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

/// Represents the allocation state of a SmartString.
/// This union tracks whether a string is constant, allocated (and by which allocator),
/// or has been freed (dead).
pub const AllocKind = union(enum) {
    /// Represents a compile-time constant string that never needs to be freed
    Constant: void,
    /// Represents an allocated string, storing the allocator that owns it
    Allocated: std.mem.Allocator,
    /// Represents a string that has been freed and should not be used
    Dead: void,

    /// Returns true if the string has been freed (is Dead)
    inline fn isDead(self: AllocKind) bool {
        return switch (self) {
            .Dead => true,
            else => false,
        };
    }

    /// Returns true if the string is currently allocated
    inline fn isAllocated(self: AllocKind) bool {
        return switch (self) {
            .Allocated => true,
            else => false,
        };
    }

    /// Returns true if the string is a compile-time constant
    inline fn isConstant(self: AllocKind) bool {
        return switch (self) {
            .Constant => true,
            else => false,
        };
    }

    /// Compares two AllocKinds for equality
    /// Two allocated strings are equal only if they use the same allocator
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

    var str_one = try SmartString.alloc("hello, world", a);
    defer str_one.deinit();

    try t.expectEqualStrings("hello, world", str_one.data);
    try t.expectEqual(AllocKind{ .Allocated = a }, str_one.kind);

    var str_two = SmartString.constant("hello, world");
    defer str_two.deinit();

    try t.expectEqualStrings("hello, world", str_two.data);
    try t.expectEqual(AllocKind{ .Constant = {} }, str_two.kind);

    try t.expectEqualStrings(str_one.data, str_two.data);
    try t.expect(!str_one.kind.eql(str_two.kind));
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

    var str_one = try SmartString.alloc("hello, world", a);
    defer str_one.deinit();

    var str_two = try str_one.clone();
    defer str_two.deinit();

    try t.expectEqualStrings("hello, world", str_one.data);
    try t.expectEqualStrings("hello, world", str_two.data);

    try t.expect(str_one.kind.eql(str_two.kind));
}
