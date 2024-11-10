pub fn main() !void {
    var timer = try Timer.start();

    const now = DateTime.now();
    const min = DateTime{ .timestamp = std.math.minInt(i64) };
    const max = DateTime{ .timestamp = std.math.maxInt(i64) };

    std.log.info("Took {d} ns", .{timer.read()});

    std.log.info("{}", .{now});
    std.log.info("{}", .{min});
    std.log.info("{}", .{max});
}

const std = @import("std");

const DateTime = @import("DateTime.zig");
const Timer = std.time.Timer;
