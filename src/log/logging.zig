const std = @import("std");
const cham = @import("chameleon");

const SmartString = @import("../util/utils.zig").SmartString;

const log = std.log;

pub const Level = log.Level;
pub const Scope = @Type(.enum_literal);

pub const Color = enum {
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    default,
};

pub const ScopeModifier = struct {
    scope: SmartString,
    prefix_match: bool = false,
    color: ?Color = .default,
    rename: ?SmartString = null,
};

const Allocator = std.mem.Allocator;

const Globals = struct {
    allocator: Allocator,

    enable_file_output: bool = false,
    output_file: ?std.fs.File = null,

    additional_scopes: std.ArrayList(ScopeModifier),

    fn initOrGetFile(self: *Globals) !std.fs.File {
        if (self.output_file) |file| {
            return file;
        } else {
            return error.NoFileSet;
        }
    }

    fn init(allocator: Allocator) !Globals {
        return .{
            .allocator = allocator,

            .enable_file_output = false,
            .output_file = null,

            .additional_scopes = std.ArrayList(ScopeModifier).init(allocator),
        };
    }

    fn deinit(self: *Globals) void {
        if (self.output_file) |file| {
            file.close();
        }

        for (self.additional_scopes.items) |*modifier| {
            if (modifier.*.rename) |*value| {
                value.deinit();
            }

            modifier.*.scope.deinit();
        }
        self.additional_scopes.deinit();

        self.* = undefined;
    }
};

var core: ?Globals = null;

pub const config = struct {
    pub fn setFileOutput(value: bool) void {
        if (core) |*globals| {
            globals.enable_file_output = value;
        } else {
            unreachable; // logging is not initialized
        }
    }

    pub fn isFileOutput() bool {
        if (core) |*globals| {
            return globals.enable_file_output;
        } else {
            unreachable; // logging is not initialized
        }
    }

    pub fn setOutputFile(file: std.fs.File) !void {
        if (core) |*globals| {
            globals.output_file = file;
        } else {
            unreachable; // logging is not initialized
        }
    }

    pub fn getOutputFile() ?*const std.fs.File {
        if (core) |*globals| {
            return &globals.output_file;
        } else {
            unreachable; // logging is not initialized
        }
    }

    pub fn addScope(modifier: ScopeModifier) !void {
        if (core) |*globals| {
            try globals.additional_scopes.append(modifier);
        } else {
            unreachable; // logging is not initialized
        }
    }
};

pub fn init(allocator: Allocator) !void {
    if (core) |_| {
        return error.AlreadyInitialized;
    }
    core = try Globals.init(allocator);
}

pub fn deinit() void {
    if (core) |*globals| {
        globals.deinit();
    }
}

/// If using this log function, you *must* call `init` before any logging occurs.
/// Otherwise, it will complain. A lot.
pub fn logFn(comptime level: Level, comptime scope: Scope, comptime format: []const u8, args: anytype) void {
    nosuspend logFnImpl(level, scope, format, args) catch |err| {
        std.debug.print("lys: error while logging: {s}\n", .{@errorName(err)});
    };
}

fn get() *Globals {
    if (core) |*globals| {
        return globals;
    }

    unreachable; // logging is not initialized
}

fn isMatch(name: []const u8, modifier: *const ScopeModifier) bool {
    if (modifier.prefix_match) {
        return std.mem.startsWith(u8, name, modifier.scope.data);
    }

    return std.mem.eql(u8, name, modifier.scope.data);
}

fn prep(name: []const u8, modifier: ?*const ScopeModifier, allocator: Allocator) ![]const u8 {
    if (!std.mem.containsAtLeastScalar(u8, name, 1, '_'))
        return name;

    var c = cham.initRuntime(.{
        .allocator = allocator,
    });

    var chunks = std.mem.tokenizeScalar(u8, name, '_');

    var output = std.ArrayList(u8).init(allocator);

    var isFirst = true;
    while (chunks.next()) |chunk| {
        if (!isFirst) {
            _ = try output.writer().write("::");
        } else {
            isFirst = false;
        }

        if (modifier) |mod| {
            if (mod.color) |color| {
                _ = switch (color) {
                    .default => try output.writer().write(chunk),
                    .blue => try output.writer().write(try c.blue().fmt("{s}", .{chunk})),
                    .green => try output.writer().write(try c.green().fmt("{s}", .{chunk})),
                    .red => try output.writer().write(try c.red().fmt("{s}", .{chunk})),
                    .white => try output.writer().write(try c.white().fmt("{s}", .{chunk})),
                    .yellow => try output.writer().write(try c.yellow().fmt("{s}", .{chunk})),
                    .magenta => try output.writer().write(try c.magenta().fmt("{s}", .{chunk})),
                    .cyan => try output.writer().write(try c.cyan().fmt("{s}", .{chunk})),
                };
            } else {
                _ = try output.writer().write(chunk);
            }
        } else {
            _ = try output.writer().write(chunk);
        }
    }

    return try output.toOwnedSlice();
}

fn logFnImpl(comptime level: Level, comptime scope: Scope, comptime format: []const u8, args: anytype) !void {
    const globals = get();
    var arena = std.heap.ArenaAllocator.init(globals.allocator);
    var c = cham.initRuntime(.{
        .allocator = arena.allocator(),
    });
    defer {
        c.deinit();
        arena.deinit();
    }

    const scopeText = scopeTextBlk: {
        switch (scope) {
            .default => break :scopeTextBlk "main",
            .gpa => {
                const gpa = "GPAlloc";

                break :scopeTextBlk try c.redBright().fmt("{s}", .{gpa});
            },

            else => {
                for (globals.additional_scopes.items) |modifier| {
                    if (isMatch(@tagName(scope), &modifier)) {
                        const text = blk: {
                            if (modifier.rename) |rename| {
                                break :blk rename.data;
                            } else {
                                break :blk try prep(@tagName(scope), &modifier, arena.allocator());
                            }
                        };

                        if (modifier.color) |color| {
                            switch (color) {
                                .default => break :scopeTextBlk text,
                                .blue => break :scopeTextBlk try c.blue().fmt("{s}", .{text}),
                                .green => break :scopeTextBlk try c.green().fmt("{s}", .{text}),
                                .red => break :scopeTextBlk try c.red().fmt("{s}", .{text}),
                                .white => break :scopeTextBlk try c.white().fmt("{s}", .{text}),
                                .yellow => break :scopeTextBlk try c.yellow().fmt("{s}", .{text}),
                                .magenta => break :scopeTextBlk try c.magenta().fmt("{s}", .{text}),
                                .cyan => break :scopeTextBlk try c.cyan().fmt("{s}", .{text}),
                            }
                        } else {
                            break :scopeTextBlk text;
                        }
                    }
                } else {
                    break :scopeTextBlk try prep(@tagName(scope), null, arena.allocator());
                }
            },
        }

        unreachable;
    };

    const levelText = switch (level) {
        .debug => try c.gray().fmt("{s: >5}", .{"DEBUG"}),
        .info => try c.white().fmt("{s: >5}", .{"INFO"}),
        .warn => try c.yellow().fmt("{s: >5}", .{"WARN"}),
        .err => try c.red().fmt("{s: >5}", .{"ERROR"}),
    };

    const prefix = try std.fmt.allocPrint(arena.allocator(), "[{s}] {s}:", .{
        levelText,
        scopeText,
    });

    const message = try std.fmt.allocPrint(arena.allocator(), format, args);

    if (globals.enable_file_output and globals.output_file != null) {
        var file = try globals.initOrGetFile();
        var writer = file.writer().any();

        nosuspend try writer.print("{s} {s}\n", .{
            prefix,
            message,
        });
    } else {
        nosuspend std.debug.print("{s} {s}\n", .{
            prefix,
            message,
        });
    }
}

const t = std.testing;

test "logFn works" {
    try init(t.allocator);
    defer deinit();

    try config.addScope(.{
        .scope = .constant("some_scope"),
        .rename = .constant("some rename"),
        .color = .green,
    });
    try config.addScope(.{
        .scope = .constant("other"),
        .rename = .constant("other rename"),
        .color = .blue,
    });
    try config.addScope(.{
        .scope = .constant("test"),
        .prefix_match = true,
        .color = .yellow,
    });

    try logFnImpl(.err, .default, "hello world", .{});
    try logFnImpl(.info, .some_scope, "hello world", .{});
    try logFnImpl(.warn, .other, "hello world", .{});
    try logFnImpl(.err, .test_scope, "hello world", .{});
}
