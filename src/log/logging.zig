const std = @import("std");
const cham = @import("chameleon");

const log = std.log;

pub const Level = log.Level;
pub const Scope = @Type(.EnumLiteral);

const Allocator = std.mem.Allocator;

const Globals = struct {
    allocator: Allocator,

    enableFileOutput: bool = false,
    outputFile: ?std.fs.File = null,

    fn arena(self: *Globals) std.heap.ArenaAllocator {
        return std.heap.ArenaAllocator.init(self.allocator);
    }

    fn init(allocator: Allocator) !Globals {
        return .{
            allocator,
        };
    }

    fn deinit(self: *Globals) void {
        if (self.outputFile) |file| {
            file.close();
        }

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
};

pub fn init(allocator: Allocator) !void {
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

fn logFnImpl(comptime level: Level, comptime scope: Scope, comptime format: []const u8, args: anytype) !void {
    var arena = core.?.arena();
    const c = cham.initRuntime(.{
        .allocator = arena.allocator(),
    });

    _ = c;

    _ = level;
    _ = scope;
    _ = format;
    _ = args;

    return error.NotImplemented;
}
