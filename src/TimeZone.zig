date: DateTime,
time_zone_list: []const TimeOffset,

const TimeZoneList = []const TimeOffset;

/// FIXME: put Interval in `DateTime` or it's own file
pub const Interval = enum(i64) { _ };

const TimeOffsetFn = *const fn (DateTime) Interval;
const TimeOffset = union(enum) {
    static: Interval,
    dynamic: TimeOffsetFn,

    pub fn getOffset(self: @This(), date: DateTime) Interval {
        return switch (self) {
            .static => |s| s,
            .dynamic => |s| s(date),
        };
    }
};

pub fn init(date: DateTime, second_offset: i64) @This() {
    return .{
        .date = date,
        .time_zone_list = &.{.{
            .static = @enumFromInt(second_offset),
        }},
    };
}

// FIXME: Ensure this never fails
pub fn localizedDate(self: @This()) DateTime {
    var updated_date = self.date;
    for (self.time_zone_list) |item| {
        // FIXME: change this to something like apply interval
        updated_date = updated_date.addSeconds(@intFromEnum(item.getOffset(self.date)));
    }
    return updated_date;
}

pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    try self.localizedDate().format(fmt, options, writer);
}

const DateTime = @import("DateTime.zig");
const std = @import("std");
