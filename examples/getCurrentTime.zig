pub fn main() !void {
    var dbg_inst: std.heap.DebugAllocator(.{}) = .init;
    defer _ = dbg_inst.deinit();
    const gpa = dbg_inst.allocator();

    var threaded: Io.Threaded = .init(gpa);
    defer threaded.deinit();
    const io = threaded.io();

    const utc_now: DateTime = try .now(io);
    std.log.info("UTC right now : {f}", .{utc_now});

    const utc_in_an_hour = utc_now.addHours(1);
    std.log.info("UTC in an hour: {f}", .{utc_in_an_hour});

    const utc_in_a_week = utc_now.addWeeks(1);
    std.log.info("UTC in a week : {f}", .{utc_in_a_week});

    const utc_in_a_month = utc_now.addMonths(1);
    std.log.info("UTC in a month: {f}", .{utc_in_a_month});

    const utc_in_a_year = utc_now.addYears(1);
    std.log.info("UTC in a year : {f}", .{utc_in_a_year});

    const timezone: TimeZone = try .find(gpa, io);
    defer timezone.deinit(gpa);

    const local_now = timezone.localize(utc_now);
    std.log.info("Local right now : {f}", .{local_now});

    const local_in_an_hour = timezone.localize(utc_in_an_hour);
    std.log.info("Local in an hour: {f}", .{local_in_an_hour});

    const local_in_a_week = timezone.localize(utc_in_a_week);
    std.log.info("Local in a week : {f}", .{local_in_a_week});

    const local_in_a_month = timezone.localize(utc_in_a_month);
    std.log.info("Local in a month: {f}", .{local_in_a_month});

    const local_in_a_year = timezone.localize(utc_in_a_year);
    std.log.info("Local in a year : {f}", .{local_in_a_year});
}

const std = @import("std");
const tig = @import("tig");

const Io = std.Io;
const DateTime = tig.DateTime;
const TimeZone = tig.TimeZone;
