//! Platform independend timezone representation. It is meant to be instanciated
//! once and then used to transform UTC times to local times.
//!
//! On unix this is firstly from TZif files, and alternatively a TZ string.
//!
//! On windows this is TODO: windows impl

data: union(enum) {
    tzif: TZif,
    tz_string: TZString,
    windows: void,

    /// We weren't able to find the systems timezone.
    ///
    /// We assume GMT, no daylight savings time
    none,
},

const TimeZone = @This();

/// Windows system time
const SYSTEMTIME = extern struct {
    wYear: windows.WORD,
    wMonth: windows.WORD,
    wDayOfWeek: windows.WORD,
    wDay: windows.WORD,
    wHour: windows.WORD,
    wMinute: windows.WORD,
    wSecond: windows.WORD,
    wMilliseconds: windows.WORD,

    pub fn getLocal() SYSTEMTIME {
        var local_time: SYSTEMTIME = undefined;
        GetLocalTime(&local_time);

        return local_time;
    }

    extern "kernel32" fn GetLocalTime(LPSYSTEMTIME: *SYSTEMTIME) callconv(.winapi) void;

    const windows = std.os.windows;
};

pub const Localization = struct {
    base_offset: i64,
    leap_second_offset: i64,
    is_dst: bool,
    is_leap_second: bool,
};

pub const Error = TZif.ParseError || std.process.GetEnvVarOwnedError;

pub fn deinit(self: TimeZone, alloc: Allocator) void {
    switch (self.data) {
        .tzif => |tzif| tzif.deinit(alloc),
        else => {},
    }
}

// TODO: Fix error set
pub fn find(alloc: Allocator, io: Io) !TimeZone {
    if (@import("builtin").os.tag == .windows) {
        return .{ .data = .{ .windows = {} } };
    }

    if (try TZif.findTzif(alloc, io)) |t| {
        return .{ .data = .{ .tzif = t } };
    }

    // According to Posix, systems should have the TZ env var, however
    // I can't find it on my machine. I'll have the check anyway
    if (std.process.hasEnvVarConstant("TZ")) blk: {
        const tz = try std.process.getEnvVarOwned(alloc, "TZ");
        defer alloc.free(tz);

        var tz_reader: Reader = .fixed(tz);

        const tz_string = TZString.parse(alloc, &tz_reader) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => break :blk,
        };

        return .{ .data = .{ .tz_string = tz_string } };
    }

    return .{ .data = .none };
}

pub fn localize(timezone: TimeZone, date: DateTime) DateTime {
    const data: Localization = switch (timezone.data) {
        .tzif => |tzif| tzifLocalization(tzif, date),
        .tz_string => |tz_str| tzStringLocalization(tz_str, date),
        .none => .{ .base_offset = 0, .leap_second_offset = 0, .is_dst = false, .is_leap_second = false },
        .windows => {
            if (@import("builtin").os.tag != .windows)
                @panic("Windows timezone can only be used on windows");

            const local_time: SYSTEMTIME = .getLocal();

            const year: Year = .from(local_time.wYear);
            const month: Month = .from(@intCast(local_time.wMonth));

            assert(local_time.wDay != 0);

            return DateTime.gregorianEpoch
                .setYear(year)
                .addDays(month.ordinalNumberOfFirstOfMonth(year.isLeapYear()))
                .addDays(local_time.wDay - 1) // wDay is 1 through 31, we need to normalize
                .addHours(local_time.wHour)
                .addMinutes(local_time.wMinute)
                .addSeconds(local_time.wSecond);
        },
    };

    return date.addSeconds(data.base_offset + data.leap_second_offset);
}

fn tzifLocalization(tzif: TZif, date: DateTime) Localization {
    assert(tzif.isValid());

    const data = tzif.data_block;
    const timestamp = date.toUnixTimestamp();

    const RelevantTransition = union(enum) {
        before,
        on: TZif.TZifDataBlock.Transition,
        after,
        none,
    };

    // relevant transition.
    // If time < first transition or time > last transition it's null
    const relevant_transition: RelevantTransition = blk: {
        if (data.transition_times.len == 0) break :blk .none;

        var prev_transition: RelevantTransition = .before;
        for (data.transition_times) |trans| {
            if (trans.unix_timestamp > timestamp)
                break :blk prev_transition;

            prev_transition = .{ .on = trans };
        }
        break :blk .after;
    };

    // FIXME: Handle this part of the spec:
    // (desig)idx:
    // A one-octet unsigned integer specifying a zero-based index into the series
    // of time zone designation octets, thereby selecting a particular designation
    // string. Each index be in the range [0, "charcnt" - 1]; it designates the
    // NUL‑terminated string of octets starting at position "idx" in the
    // time zone designations. (This string MAY be empty.) A NUL octet MUST exist
    // in the time zone designations at or after position "idx". If the designation
    // string is "-00", the time type is a placeholder indicating that
    // local time is unspecified.
    const base_offset: i64, const is_dst = blk: {
        switch (relevant_transition) {
            .on => |t| {
                const record = data.local_time_type_records[t.idx];
                break :blk .{ record.offset, record.daylight_savings_time };
            },

            // If we are before any transition, we don't want to look at the footer
            // as it's meant for _after_ the transitions
            //
            // TODO: Do a sanity check on this when it's not 4 am
            .before => {
                const idx = data.transition_times[0].idx;
                const record = data.local_time_type_records[idx];
                break :blk .{ record.offset, record.daylight_savings_time };
            },
            else => {},
        }

        // Then check if we can be smart and use the footer
        if (tzif.footer) |footer| {
            const tz_loc = tzStringLocalization(footer.tz_string, date);

            break :blk .{ tz_loc.base_offset, tz_loc.is_dst };
        }

        // Do a last ditch effort
        switch (relevant_transition) {
            .after => {
                const idx = data.transition_times[data.transition_times.len - 1].idx;
                const record = data.local_time_type_records[idx];
                break :blk .{ record.offset, record.daylight_savings_time };
            },

            // We really have no information here, assume GMT, no dst
            .none => break :blk .{ 0, false },

            // Already handled
            .on, .before => unreachable,
        }
    };

    // FIXME: deal with this part of the spec
    // If "leapcnt" is zero, LEAPCORR is zero for all timestamps.
    // If "leapcnt" is nonzero, for timestamps before the first occurrence time,
    // LEAPCORR is zero if the first correction is one (1) or minus one (-1) and
    // is unspecified otherwise (which can happen only in files truncated at the
    // start (Section 6.1)).
    const leap_second_offset: i32, const is_leap_second: bool = blk: {
        if (tzif.header.leapcnt == 0) break :blk .{ 0, false };

        if (data.leap_second_expiration) |exp| {
            if (exp < timestamp)
                log.warn("Leap second table expired for timestamp", .{});
        }

        // The occurance goes up or down by 1 depending on a positive or negative
        // leap second. This means that the previous correction is equal to the
        // amount of leap seconds
        var prev_correction: i32 = 0;
        for (data.leap_second_records) |leap| {
            if (leap.occurrence >= timestamp)
                break :blk .{ prev_correction, leap.occurrence == timestamp };

            prev_correction = leap.correction;
        }
        break :blk .{ prev_correction, false };
    };

    return .{
        .base_offset = base_offset,
        .leap_second_offset = leap_second_offset,
        .is_dst = is_dst,
        .is_leap_second = is_leap_second,
    };
}

fn tzStringLocalization(tz_string: TZString, date: DateTime) Localization {
    if (tz_string.rule == null or tz_string.daylight_savings_time == null) return .{
        .base_offset = tz_string.standard.offset.toSecond(),

        // No way figure out dst
        .is_dst = false,

        // No way to represent leap seconds
        .leap_second_offset = 0,
        .is_leap_second = false,
    };

    const order = struct {
        pub fn order(off: TZString.Rule.DateOffset.Resolved, dt: DateTime) std.math.Order {
            switch (std.math.order(dt.getDayOfYear().to(), off.doy.to())) {
                .lt, .gt => |o| return o,
                .eq => {},
            }
            switch (std.math.order(dt.getHour().to(), off.hour.to())) {
                .lt, .gt => |o| return o,
                .eq => {},
            }
            switch (std.math.order(dt.getMinute().to(), off.minute.to())) {
                .lt, .gt => |o| return o,
                .eq => {},
            }
            switch (std.math.order(dt.getSecond().to(), off.second.to())) {
                .lt, .gt => |o| return o,
                .eq => {},
            }

            return .eq;
        }
    }.order;

    const year = date.getYear();

    const rule = tz_string.rule.?;
    const dst = tz_string.daylight_savings_time.?;
    const standard = tz_string.standard;

    const start = rule.start.resolve(year);
    const end = rule.end.resolve(year);

    const order_start = order(start, date);
    const order_end = order(end, date);

    const base_offset, const is_dst =
        if (rule.end.order(rule.start, year) != .lt)
            if (order_start != .lt and order_end == .lt)
                .{ dst.offset, true }
            else
                .{ standard.offset, false }
        else if (order_start != .lt or order_end == .lt)
            .{ dst.offset, true }
        else
            .{ standard.offset, false };

    return .{
        .base_offset = base_offset.toSecond(),
        .is_dst = is_dst,

        // No way to represent leap seconds
        .is_leap_second = false,
        .leap_second_offset = 0,
    };
}

test tzStringLocalization {
    const expectEqual = std.testing.expectEqual;

    const tzstring: TZString = .{
        .standard = .{
            .name = "STD",
            .offset = .{ .hour = 0 },
        },
        .daylight_savings_time = .{
            .name = "DST",
            .offset = .{ .hour = 1 },
        },
        .rule = .{
            .start = .{
                .date = .{ .julian = 10 },
                .offset = .{ .hour = 0 },
            },
            .end = .{
                .date = .{ .julian = 20 },
                .offset = .{ .hour = 0 },
            },
        },
    };

    const jan1 = DateTime.build(.{ .year = 0, .month = .January, .day_of_month = 1 });
    const jan1_loc: Localization = .{ .base_offset = 0, .leap_second_offset = 0, .is_dst = false, .is_leap_second = false };
    try expectEqual(jan1_loc, tzStringLocalization(tzstring, jan1));

    const jan10 = DateTime.build(.{ .year = 0, .month = .January, .day_of_month = 10 });
    const jan10_loc: Localization = .{ .base_offset = 3600, .leap_second_offset = 0, .is_dst = true, .is_leap_second = false };
    try expectEqual(jan10_loc, tzStringLocalization(tzstring, jan10));

    const jan20 = DateTime.build(.{ .year = 0, .month = .January, .day_of_month = 20 });
    const jan20_loc: Localization = .{ .base_offset = 0, .leap_second_offset = 0, .is_dst = false, .is_leap_second = false };
    try expectEqual(jan20_loc, tzStringLocalization(tzstring, jan20));
}

const std = @import("std");

const log = std.log.scoped(.timezone);
const assert = std.debug.assert;

const Io = std.Io;
const Reader = Io.Reader;
const Writer = Io.Writer;
const Allocator = std.mem.Allocator;
const DateTime = @import("DateTime.zig");
const TZif = @import("TZif.zig");
const TZString = @import("TZString.zig");
const Year = DateTime.Year;
const Month = DateTime.MonthOfYear;

test {
    // Ensure this compiles
    _ = &find;
    _ = &localize;
}
