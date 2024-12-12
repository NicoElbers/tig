const DateTime = @import("src/DateTime.zig");

pub fn main() !void {
    const timestamp = std.time.timestamp();

    var timer = std.time.Timer.start() catch unreachable;
    const date = DateTime.fromUnixTimestamp(timestamp);
    const year = date.getYear();
    const month = date.getMonth();
    const day_of_month = date.getDayOfMonth();
    const hour = date.getHour();
    const minute = date.getMinute();
    const seconds = date.getSecond();
    std.debug.print("{d} ns\n", .{timer.read()});

    std.debug.print("Min day: {}\n", .{DateTime.date_min});
    std.debug.print("max day: {}\n", .{DateTime.date_max});

    std.debug.print("Today: {}; {}-{}-{}T{}:{}:{}\n", .{
        date,
        year,
        month,
        day_of_month,
        hour,
        minute,
        seconds,
    });
}

const std = @import("std");
