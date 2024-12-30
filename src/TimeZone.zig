//! Platform independend timezone representation. It is meant to be instanciated
//! once and then used to transform UTC times to local times.
//!
//! On unix this is firstly from TZif files, and alternatively a TZ string.
//!
//! On windows this is TODO: windows impl

data: union(enum) {
    tzif: TZif,
    tz_string: TZString,
},

pub const Localization = struct {
    base_offset: i64,
    leap_second_offset: i64,
    is_dst: bool,
};

pub fn localize(timezone: TimeZone, date: DateTime) DateTime {
    const data: Localization = switch (timezone.data) {
        .tzif => |tzif| tzifLocalization(tzif, date),
        else => unreachable,
    };

    return date.addSeconds(data.base_offset + data.leap_second_offset);
}

pub fn localFormat(timezone: TimeZone, date: DateTime, writer: AnyWriter) !void {
    _ = timezone;
    _ = date;
    _ = writer;
}

fn tzifLocalization(tzif: TZif, date: DateTime) Localization {
    const data = tzif.data_block;
    const timestamp = date.toUnixTimestamp();

    // relevant transition.
    // If time < first transition or time > last transition it's null
    const relevant_transition: ?TZif.TZifDataBlock.Transition = blk: {
        var prev_transition: ?TZif.TZifDataBlock.Transition = null;
        for (data.transition_times) |trans| {
            if (trans.unix_timestamp > timestamp)
                break :blk prev_transition;

            prev_transition = trans;
        }
        break :blk null;
    };

    const base_offset: i64 = blk: {
        if (relevant_transition) |trans|
            break :blk data.local_time_type_records[trans.idx].offset;

        unreachable;
    };

    const leap_second_offset: i64 = blk: {
        if (data.leap_second_expiration) |exp| {
            if (exp < timestamp)
                log.warn("Leap second table expired for timestamp", .{});
        }

        var sum: i64 = 0;
        for (data.leap_second_records) |leap| {
            if (leap.occurrence >= timestamp) break :blk sum;

            if (leap.correction >= 0)
                sum += 1
            else
                sum -= 1;
        }

        break :blk sum;
    };

    const is_dst: bool = blk: {
        if (relevant_transition) |trans|
            break :blk data.local_time_type_records[trans.idx].daylight_savings_time;

        unreachable;
    };

    return .{
        .base_offset = base_offset,
        .leap_second_offset = leap_second_offset,
        .is_dst = is_dst,
    };
}

const TimeZone = @This();

const DateTime = @import("DateTime.zig");
const TZif = @import("TZif.zig");
const TZString = @import("TZString.zig");

const std = @import("std");
const log = std.log.scoped(.timezone);

const AnyWriter = std.io.AnyWriter;
