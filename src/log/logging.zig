const std = @import("std");
const cham = @import("chameleon");

const log = std.log;

pub const Level = log.Level;
pub const Scope = @Type(.EnumLiteral);

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
    scope: []const u8,
    color: ?Color = .default,
    bright: bool = false,
    rename: ?[]const u8 = null,
};

const Allocator = std.mem.Allocator;

const Globals = struct {
    allocator: Allocator,

    enableFileOutput: bool = false,
    outputFile: ?std.fs.File = null,

    additionalScopes: std.ArrayList(ScopeModifier),

    fn arena(self: *Globals) std.heap.ArenaAllocator {
        return std.heap.ArenaAllocator.init(self.allocator);
    }

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

            .additionalScopes = std.ArrayList(ScopeModifier).init(allocator),
        };
    }

    fn deinit(self: *Globals) void {
        if (self.outputFile) |file| {
            file.close();
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
    core = try Globals.init(allocator);
}

pub fn deinit() void {
    if (core) |*globals| {
        globals.deinit();
    }
}

var longestScopeYet: usize = 0;

/// If using this log function, you *must* call `init` before any logging occurs.
/// Otherwise, it will complain. A lot.
pub fn logFn(comptime level: Level, comptime scope: Scope, comptime format: []const u8, args: anytype) void {
    nosuspend logFnImpl(level, scope, format, args) catch |err| {
        std.debug.print("lys: error while logging: {s}\n", .{@errorName(err)});
    };
}

fn get() !*Globals {
    var cor = core;
    if (cor) |*co| {
        return co;
    }

    unreachable; // logging is not initialized
}

fn logFnImpl(comptime level: Level, comptime scope: Scope, comptime format: []const u8, args: anytype) !void {
    const globals = try get();
    var arena = globals.arena();
    const c = cham.initRuntime(.{
        .allocator = arena.allocator(),
    });
    defer {
        c.deinit();
        arena.deinit();
    }

    var scopeLen: usize = 4;
    const scopeText = switch (scope) {
        .default => "main",
        .gpa => gpaBlock: {
            const gpa = "General Purpose Allocator";
            scopeLen = gpa;

            break :gpaBlock try c.redBright().fmt("{s}", .{gpa});
        },

        else => elseBlock: {
            for (globals.additionalScopes.items) |modifier| {
                if (std.mem.eql(u8, modifier.scope, @tagName(scope))) {
                    const text = blk: {
                        if (modifier.rename) |rename| {
                            break :blk rename;
                        } else {
                            break :blk @tagName(scope);
                        }
                    };

                    scopeLen = text.len;

                    if (modifier.color) |color| {
                        switch (color) {
                            .default => break :elseBlock text,
                            .blue => break :elseBlock try c.blue().fmt("{s}", .{text}),
                            .green => break :elseBlock try c.green().fmt("{s}", .{text}),
                            .red => break :elseBlock try c.red().fmt("{s}", .{text}),
                            .white => break :elseBlock try c.white().fmt("{s}", .{text}),
                            .yellow => break :elseBlock try c.yellow().fmt("{s}", .{text}),
                            .magenta => break :elseBlock try c.magenta().fmt("{s}", .{text}),
                            .cyan => break :elseBlock try c.cyan().fmt("{s}", .{text}),
                        }
                    } else {
                        break :elseBlock text;
                    }
                }
            }
        },
    };

    longestScopeYet = std.math.max(longestScopeYet, scopeLen);

    const levelText = switch (level) {
        .debug => try c.gray().fmt("{s: >5}", .{"DEBUG"}),
        .info => try c.white().fmt("{s: >5}", .{"INFO"}),
        .warn => try c.yellow().fmt("{s: >5}", .{"WARN"}),
        .err => try c.red().fmt("{s: >5}", .{"ERROR"}),
    };

    const paddingLen = longestScopeYet - scopeLen;

    const padding = try arena.allocator().alloc(u8, paddingLen);
    for (padding) |*p| p.* = ' ';

    const prefix = try std.fmt.allocPrint(arena.allocator(), "[{s}] [{s}{s}]", .{
        levelText,
        padding,
        scopeText,
    });

    const message = try std.fmt.allocPrint(arena.allocator(), format, args);

    if (globals.enableFileOutput) {
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
