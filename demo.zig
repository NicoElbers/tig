pub fn main() !void {
    var gpa_inst = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_inst.deinit();

    const gpa = gpa_inst.allocator();

    const tz: TimeZone = try .find(gpa);
    defer tz.deinit(gpa);

    const now = tz.localize(.now());

    std.log.info("now: {}", .{now});
}

const DateTime = @import("src/DateTime.zig");
const TimeZone = @import("src/TimeZone.zig");

const std = @import("std");
