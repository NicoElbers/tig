pub fn main() !void {
    var dbg_inst: std.heap.DebugAllocator(.{}) = .init;
    defer _ = dbg_inst.deinit();
    const gpa = dbg_inst.allocator();

    var threaded: Io.Threaded = .init(gpa);
    defer threaded.deinit();
    const io = threaded.io();

    const timezone: TimeZone = try .find(gpa, io);
    defer timezone.deinit(gpa);

    const now = timezone.localize(try .now(io));

    std.log.info("Default DateTime: {f}", .{now});
    std.log.info("Calendar days since 0000-01-01: {f}", .{now.getCalendarDay()});
    std.log.info("Calendar weeks since 0000-01-01: {f}", .{now.getWeek()});
    std.log.info("Seconds since 0000-01-01: {d}", .{now.timestamp});
    std.log.info("Seconds since 1970-01-01: {d}", .{now.toUnixTimestamp()});
    std.log.info("Year of Date: {f}", .{now.getYear()});
    std.log.info("Day of Year: {f}", .{now.getDayOfYear()});
    std.log.info("Month of Year: {f}", .{now.getMonth().fmt(.name)});
    std.log.info("Month of Year: {f}", .{now.getMonth().fmt(.short)});
    std.log.info("Month of Year: {f}", .{now.getMonth().fmt(.number)});
    std.log.info("Day of Month: {f}", .{now.getDayOfMonth().fmt(now.getMonth(), now.getYear().isLeapYear())});
    std.log.info("Week of the year: {f}", .{now.getWeekOfYear().fmt(now.getYear())});
    std.log.info("Day of Week: {f}", .{now.getDayOfWeek().fmt(.name)});
    std.log.info("Day of Week: {f}", .{now.getDayOfWeek().fmt(.short)});
    std.log.info("Day of Week: {f}", .{now.getDayOfWeek().fmt(.number)});
    std.log.info("Hour of Day: {f}", .{now.getHour()});
    std.log.info("Minute of Hour: {f}", .{now.getMinute()});
    std.log.info("Second of Minute: {f}", .{now.getSecond()});
}

const std = @import("std");
const tig = @import("tig");

const Io = std.Io;
const DateTime = tig.DateTime;
const TimeZone = tig.TimeZone;
