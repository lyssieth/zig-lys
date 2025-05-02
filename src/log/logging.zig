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
    color: ?Color = .default,
    bright: bool = false,
    rename: ?SmartString = null,
};

const Allocator = std.mem.Allocator;

const Globals = struct {
    allocator: Allocator,

    enableFileOutput: bool = false,
    outputFile: ?std.fs.File = null,

    additionalScopes: std.ArrayList(ScopeModifier),

    fn initOrGetFile(self: *Globals) !std.fs.File {
        if (self.outputFile) |file| {
            return file;
        } else {
            return error.NoFileSet;
        }
    }

    fn init(allocator: Allocator) !Globals {
        return .{
            .allocator = allocator,

            .enableFileOutput = false,
            .outputFile = null,

            .additionalScopes = std.ArrayList(ScopeModifier).init(allocator),
        };
    }

    fn deinit(self: *Globals) void {
        if (self.outputFile) |file| {
            file.close();
        }

        for (self.additionalScopes.items) |*modifier| {
            if (modifier.*.rename) |*value| {
                value.deinit();
            }

            modifier.*.scope.deinit();
        }
        self.additionalScopes.deinit();

        self.* = undefined;
    }
};

var core: ?Globals = null;

pub const config = struct {
    pub fn enableFileOutput(value: bool) void {
        if (core) |*globals| {
            globals.enableFileOutput = value;
        } else {
            unreachable; // logging is not initialized
        }
    }

    pub fn isFileOutput() bool {
        if (core) |*globals| {
            return globals.enableFileOutput;
        } else {
            unreachable; // logging is not initialized
        }
    }

    pub fn setOutputFile(file: std.fs.File) !void {
        if (core) |*globals| {
            globals.outputFile = file;
        } else {
            unreachable; // logging is not initialized
        }
    }

    pub fn getOutputFile() ?*const std.fs.File {
        if (core) |*globals| {
            return &globals.outputFile;
        } else {
            unreachable; // logging is not initialized
        }
    }

    pub fn addScope(modifier: ScopeModifier) !void {
        if (core) |*globals| {
            try globals.additionalScopes.append(modifier);
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
                for (globals.additionalScopes.items) |modifier| {
                    if (std.mem.eql(u8, modifier.scope.data, @tagName(scope))) {
                        const text = blk: {
                            if (modifier.rename) |rename| {
                                break :blk rename.data;
                            } else {
                                break :blk @tagName(scope);
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
                    break :scopeTextBlk @tagName(scope);
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

    if (globals.enableFileOutput and globals.outputFile != null) {
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
        .scope = SmartString.constant("someScope"),
        .rename = SmartString.constant("some rename"),
        .color = .green,
    });
    try config.addScope(.{
        .scope = SmartString.constant("other"),
        .rename = SmartString.constant("other rename"),
        .color = .blue,
    });

    try logFnImpl(.err, .default, "hello world", .{});
    try logFnImpl(.info, .someScope, "hello world", .{});
    try logFnImpl(.warn, .other, "hello world", .{});
}
