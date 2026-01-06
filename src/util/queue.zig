const std = @import("std");
const Atomic = std.atomic.Value;

pub fn MPSCQueue(comptime T: type) type {
    return struct {
        buffer: std.ArrayList(T),
        head: Atomic(usize),
        tail: Atomic(usize),
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .buffer = try std.ArrayList(T).initCapacity(allocator, 0),
                .head = Atomic(usize).init(0),
                .tail = Atomic(usize).init(0),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit(self.allocator);
        }

        pub fn push(self: *Self, item: T) !void {
            const tail = self.tail.load(.monotonic);

            // Ensure capacity
            if (tail >= self.buffer.items.len) {
                const new_capacity = if (self.buffer.items.len == 0) 8 else self.buffer.items.len * 2;
                try self.buffer.resize(self.allocator, new_capacity);
            }

            // Store item and update tail
            self.buffer.items[tail] = item;
            self.tail.store(tail + 1, .release);
        }

        pub fn pop(self: *Self) ?T {
            while (true) {
                const head = self.head.load(.acquire);
                const tail = self.tail.load(.acquire);

                if (head >= tail) {
                    return null;
                }

                const item = self.buffer.items[head];

                if (self.head.cmpxchgStrong(head, head + 1, .acq_rel, .monotonic)) |_| {
                    continue;
                }

                return item;
            }
        }

        pub fn isEmpty(self: *Self) bool {
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);
            return head >= tail;
        }
    };
}

const t = std.testing;

test "MPSC Queue basic operations" {
    var queue = try MPSCQueue(i32).init(t.allocator);
    defer queue.deinit();

    try queue.push(1);
    try queue.push(2);
    try queue.push(3);

    try t.expect(queue.pop().? == 1);
    try t.expect(queue.pop().? == 2);
    try t.expect(queue.pop().? == 3);
    try t.expect(queue.pop() == null);
}

const expected = [_]i32{ 1, 2, 3, 4, 5 };

fn threadOne(queue: *MPSCQueue(i32)) !void {
    var i: usize = 0;
    while (queue.pop()) |item| : (i += 1) {
        try t.expectEqual(expected[i], item);
    }
}

fn threadTwo(queue: *MPSCQueue(i32)) !void {
    for (expected) |item| {
        try queue.push(item);
    }
}

test "MPSC Threaded" {
    const Thread = std.Thread;

    var q = try MPSCQueue(i32).init(t.allocator);
    defer q.deinit();

    const t1 = try Thread.spawn(.{ .allocator = t.allocator }, threadOne, .{&q});
    const t2 = try Thread.spawn(.{ .allocator = t.allocator }, threadTwo, .{&q});

    t1.join();
    t2.join();
}
