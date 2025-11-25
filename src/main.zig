pub fn main() !void {
    var dbg_inst = std.heap.DebugAllocator(.{}).init;
    defer _ = dbg_inst.deinit();
    const gpa = dbg_inst.allocator();

    var threaded: Io.Threaded = .init(gpa);
    defer threaded.deinit();
    const io = threaded.io();

    var timer = try Timer.start();

    const tz: TimeZone = try .find(gpa, io);
    defer tz.deinit(gpa);

    const now = try DateTime.now(io);
    const local_now = tz.localize(now);

    std.log.info("Took {d} ns", .{timer.read()});

    std.log.info("UTC   time: {f}", .{now});
    std.log.info("Local time: {f}", .{local_now});
    std.log.info("Min   time: {f}", .{DateTime.date_max});
    std.log.info("Max   time: {f}", .{DateTime.date_min});
}

const std = @import("std");

const DateTime = @import("DateTime.zig");
const TimeZone = @import("TimeZone.zig");
const Timer = std.time.Timer;
const Io = std.Io;
