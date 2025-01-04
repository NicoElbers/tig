standard: Zone,
daylight_savings_time: ?Zone = null,
rule: ?Rule = null,

pub const Error = error{
    InvalidTzString,
    InvalidName,
    InvalidOffset,
    InvalidRule,
    InvalidDate,
} || Allocator.Error || std.fmt.ParseIntError ||
    DayOfWeek.Error || MonthOfYear.Error ||
    Hour.Error || Minute.Error || Second.Error;

pub const Zone = struct {
    name: []const u8,
    offset: Offset,

    pub fn deinit(self: Zone, alloc: Allocator) void {
        alloc.free(self.name);
    }
};

pub const Rule = struct {
    start: DateOffset,
    end: DateOffset,

    pub const DateOffset = struct {
        date: Date,
        offset: Offset,

        /// Returns a type safe representation that notably does not include
        /// negative hours
        pub fn resolve(do: DateOffset, year: Year) struct {
            doy: DayOfYear,
            hour: Hour,
            minute: Minute,
            second: Second,
        } {
            const offset = do.offset;

            const start_doy_num = do.date.toDayOfYear(year).to();
            const days_in_year = year.getDaysInYear();

            const day_offset: i10, const hour_resolved: u5 = res: {
                const days_guess = @divFloor(offset.hour, 24);
                const hour_guess = @mod(offset.hour, 24);

                // If we have a negative amount of hours, we are in the previous
                // day, and the new hour is 24 - old
                //
                // For a specific example, -1 hours, goes to the previous day 23 hours
                break :res if (hour_guess < 0)
                    .{ days_guess - 1, @intCast(24 + hour_guess) }
                else
                    .{ days_guess, @intCast(hour_guess) };
            };

            const resolved_doy: u9 = @intCast(@mod(days_in_year + start_doy_num + day_offset, days_in_year));

            return .{
                .doy = DayOfYear.from(resolved_doy, year.isLeapYear()),
                .hour = Hour.from(hour_resolved),
                .minute = Minute.from(offset.minute),
                .second = Second.from(offset.second),
            };
        }

        pub fn order(a: DateOffset, b: DateOffset, year: Year) enum { lt, eq, gt } {
            const a_resolved = a.resolve(year);
            const b_resolved = b.resolve(year);

            if (a_resolved.doy.to() < b_resolved.doy.to()) return .lt;
            if (a_resolved.doy.to() > b_resolved.doy.to()) return .gt;

            if (a_resolved.hour.to() < b_resolved.hour.to()) return .lt;
            if (a_resolved.hour.to() > b_resolved.hour.to()) return .gt;

            if (a_resolved.minute.to() < b_resolved.minute.to()) return .lt;
            if (a_resolved.minute.to() > b_resolved.minute.to()) return .gt;

            if (a_resolved.second.to() < b_resolved.second.to()) return .lt;
            if (a_resolved.second.to() > b_resolved.second.to()) return .gt;

            return .eq;
        }
    };

    pub const OccurenceInMonth = struct {
        month: MonthOfYear,
        day_of_week: DayOfWeek,
        occurence: u3,
    };

    pub const Date = union(enum) {
        /// The Julian day n (1 <= n <= 365). Leap days shall not be counted.
        /// That is, in all years-including leap years-February 28 is day 59 and
        /// March 1 is day 60. It is impossible to refer explicitly to the
        /// occasional February 29.
        julian: u9,
        /// The zero-based Julian day (0 <= n <= 365). Leap days shall be counted,
        /// and it is possible to refer to February 29
        zero_julian: u9,
        /// The d'th day (0 <= d <= 6) of week n of month m of the year
        /// (1 <= n <= 5, 1 <= m <= 12, where week 5 means "the last d day
        /// in month m" which may occur in either the fourth or the fifth week).
        /// Week 1 is the first week in which the d'th day occurs.
        /// Day zero is Sunday.
        ///
        /// I read this as the nth occurance of day d in month m
        occurenceInMonth: OccurenceInMonth,

        pub fn toDayOfYear(self: Date, year: Year) DayOfYear {
            return switch (self) {
                .julian => |n| {
                    const is_leap_year = year.isLeapYear();

                    return if (is_leap_year and n >= 60)
                        DayOfYear.from(n + 1, true)
                    else
                        DayOfYear.from(n, false);
                },

                .zero_julian => |n| DayOfYear.from0(n, false),
                .occurenceInMonth => |o| {
                    const is_leap_year = year.isLeapYear();

                    const first_day = year.firstDay();
                    const first_of_month = o.month.ordinalNumberOfFirstOfMonth(is_leap_year);
                    const first_day_of_month = first_day.dowAfterNDays(first_of_month);

                    const days_till_next_occurance = 7 +
                        @as(u9, first_day_of_month.toOrdinal()) +
                        @as(u9, o.day_of_week.toOrdinal());

                    const days_till_first_occurance = @mod(days_till_next_occurance, 7);

                    const days_till_relevant_occurance = (o.occurence - 1) * 7 +
                        days_till_first_occurance;

                    // TODO: remove this assert later, but it's useful for debugging
                    assert(days_till_relevant_occurance < o.month.daysInMonth(is_leap_year));

                    return DayOfYear.from0(first_of_month + days_till_relevant_occurance, is_leap_year);
                },
            };
        }
    };
};

pub const Offset = struct {
    hour: i9,
    second: u6 = 0,
    minute: u6 = 0,

    pub fn toSecond(o: Offset) i64 {
        return @as(i64, o.hour) * std.time.s_per_hour +
            @as(i64, o.minute) * std.time.s_per_min +
            @as(i64, o.second);
    }
};

pub fn deinit(tz: TZString, alloc: Allocator) void {
    tz.standard.deinit(alloc);

    if (tz.daylight_savings_time) |dst| {
        dst.deinit(alloc);
    }
}

/// Returns a subslice of buf and the index after the name
fn parseName(buf: []const u8) !struct { []const u8, usize } {
    if (buf.len == 0) return Error.InvalidName;

    var start: usize = 0;
    const state: enum { quoted, unquoted } = switch (buf[0]) {
        '<' => blk: {
            start = 1;
            break :blk .quoted;
        },
        else => .unquoted,
    };

    for (buf[start..], start..) |c, i| {
        switch (c) {
            'a'...'z',
            'A'...'Z',
            => {},
            '0'...'9',
            '+',
            '-',
            => {
                if (state == .unquoted) {
                    if (i < 2) return Error.InvalidName;
                    return .{ buf[0..i], i };
                }
            },
            '>' => {
                if (state == .unquoted) return Error.InvalidName;

                // Be sure to exclude <>, and skip the final >
                return .{ buf[1..i], i + 1 };
            },
            else => {
                if (state == .quoted) return Error.InvalidName;
                if (i < 2) return Error.InvalidName;
                return .{ buf[0..i], i };
            },
        }
    }

    return Error.InvalidTzString;
}

fn parseOffset(buf: []const u8) !struct { Offset, usize } {
    var start: usize = 0;
    const hour: i9 = blk: {
        for (buf[start..], start..) |c, i| {
            switch (c) {
                '0'...'9',
                '+',
                '-',
                => {},
                ':' => {
                    const hour = try std.fmt.parseInt(i9, buf[start..i], 10);
                    start = i + 1; // Skip :

                    if (hour < -167 or hour > 167) return Error.InvalidOffset;

                    break :blk hour;
                },
                else => {
                    const hour = try std.fmt.parseInt(i9, buf[start..i], 10);
                    start = i;

                    if (hour < -167 or hour > 167) return Error.InvalidOffset;

                    return .{ .{ .hour = hour }, start };
                },
            }
        }

        const hour = try std.fmt.parseInt(i9, buf[start..], 10);
        if (hour < -167 or hour > 167) return Error.InvalidOffset;
        return .{ .{ .hour = hour }, buf.len };
    };

    const minute: u6 = blk: {
        for (buf[start..], start..) |c, i| {
            switch (c) {
                '0'...'9',
                => {},
                ':' => {
                    const minute = try std.fmt.parseInt(u6, buf[start..i], 10);
                    start = i + 1; // Skip :

                    _ = try Minute.fromChecked(minute);

                    break :blk minute;
                },
                else => {
                    const minute = try std.fmt.parseInt(u6, buf[start..i], 10);
                    start = i;

                    _ = try Minute.fromChecked(minute);

                    return .{ .{ .hour = hour, .minute = minute }, i };
                },
            }
        }

        const minute = try std.fmt.parseInt(u6, buf[start..], 10);
        _ = try Minute.fromChecked(minute);
        return .{ .{ .hour = hour, .minute = minute }, buf.len };
    };

    for (buf[start..], start..) |c, i| {
        switch (c) {
            '0'...'9',
            => {},
            else => {
                const second = try std.fmt.parseInt(u6, buf[start..i], 10);
                _ = try Second.fromChecked(second);
                return .{ .{ .hour = hour, .minute = minute, .second = second }, i };
            },
        }
    }

    const second = try std.fmt.parseInt(u6, buf[start..], 10);
    _ = try Minute.fromChecked(second);
    return .{ .{ .hour = hour, .minute = minute, .second = second }, buf.len };
}

fn parseDate(buf: []const u8) !struct { Rule.Date, usize } {
    if (buf.len == 0) return Error.InvalidDate;

    var start: usize = 0;

    const state: enum { julian, zero_julian, occurance_in_month } = switch (buf[0]) {
        '0'...'9' => .zero_julian,
        'J' => blk: {
            start = 1;
            break :blk .julian;
        },
        'M' => blk: {
            start = 1;
            break :blk .occurance_in_month;
        },
        else => return Error.InvalidDate,
    };

    return blk: switch (state) {
        .zero_julian => {
            for (buf[start..], start..) |c, i| {
                switch (c) {
                    '0'...'9' => {},
                    else => {
                        const n = try std.fmt.parseInt(u9, buf[start..i], 10);

                        if (n > 365) return Error.InvalidDate;

                        break :blk .{ .{ .zero_julian = n }, i };
                    },
                }
            }
            const n = try std.fmt.parseInt(u9, buf[start..], 10);

            if (n > 365) return Error.InvalidDate;

            break :blk .{ .{ .zero_julian = n }, buf.len };
        },
        .julian => {
            for (buf[start..], start..) |c, i| {
                switch (c) {
                    '0'...'9' => {},
                    else => {
                        const n = try std.fmt.parseInt(u9, buf[start..i], 10);
                        if (365 < n or n < 1) return Error.InvalidDate;
                        break :blk .{ .{ .julian = n }, i };
                    },
                }
            }

            const n = try std.fmt.parseInt(u9, buf[start..], 10);
            if (365 < n or n < 1) return Error.InvalidDate;
            break :blk .{ .{ .julian = n }, buf.len };
        },
        .occurance_in_month => {
            const month = month: {
                for (buf[start..], start..) |c, i| {
                    switch (c) {
                        '0'...'9' => {},
                        '.' => {
                            const n = try std.fmt.parseInt(u4, buf[start..i], 10);
                            start = i + 1; // Skip the .

                            break :month try MonthOfYear.fromChecked(n);
                        },
                        else => return Error.InvalidDate,
                    }
                }
                return Error.InvalidDate;
            };

            const occurence = occurence: {
                for (buf[start..], start..) |c, i| {
                    switch (c) {
                        '0'...'9' => {},
                        '.' => {
                            const n = try std.fmt.parseInt(u3, buf[start..i], 10);
                            start = i + 1; // Skip the .

                            if (5 < n or n < 1) return Error.InvalidDate;

                            break :occurence n;
                        },
                        else => return Error.InvalidDate,
                    }
                }
                return Error.InvalidDate;
            };

            const day = day: {
                for (buf[start..], start..) |c, i| {
                    switch (c) {
                        '0'...'9' => {},
                        else => {
                            const n = try std.fmt.parseInt(u3, buf[start..i], 10);
                            start = i;

                            break :day (try DayOfWeek.from0Checked(n)).prev();
                        },
                    }
                }
                return Error.InvalidDate;
            };

            break :blk .{
                .{ .occurenceInMonth = .{
                    .month = month,
                    .occurence = occurence,
                    .day_of_week = day,
                } },
                start,
            };
        },
    };
}

pub fn parse(alloc: Allocator, buf: []const u8) Error!struct { TZString, usize } {
    // No chars, error
    if (buf.len == 0) return Error.InvalidTzString;

    var start: usize = 0;

    assert(start < buf.len);
    const std_name = blk: {
        const std_name_slice, const i = try parseName(buf[start..]);
        start += i;

        // No std offset, error
        if (start >= buf.len) return Error.InvalidName;

        break :blk try alloc.dupe(u8, std_name_slice);
    };
    errdefer alloc.free(std_name);

    assert(start < buf.len);
    const std_offset = blk: {
        const std_offset, const i = try parseOffset(buf[start..]);
        start += i;

        // No dst
        if (start >= buf.len) return .{ .{
            .standard = .{
                .name = std_name,
                .offset = std_offset,
            },
        }, start };

        break :blk std_offset;
    };

    assert(start < buf.len);
    const dst_name = blk: {
        const dst_name_slice, const i = parseName(buf[start..]) catch {

            // Invalid dst
            return .{ .{
                .standard = .{
                    .name = std_name,
                    .offset = std_offset,
                },
            }, start };
        };
        start += i;

        const dst_name = try alloc.dupe(u8, dst_name_slice);

        // No dst offset
        if (start >= buf.len) {
            var dst_offset = std_offset;
            dst_offset.hour += 1;

            return .{ .{
                .standard = .{
                    .name = std_name,
                    .offset = std_offset,
                },
                .daylight_savings_time = .{
                    .name = dst_name,
                    .offset = dst_offset,
                },
            }, start };
        }

        break :blk dst_name;
    };
    errdefer alloc.free(dst_name);

    assert(start < buf.len);
    const dst_offset = blk: {
        // Ignore offset, continue on to rule
        if (buf[start] == ',') {
            start += 1;

            var dst_offset = std_offset;
            dst_offset.hour += 1;

            break :blk dst_offset;
        }

        const dst_offset, const i = parseOffset(buf[start..]) catch {
            var dst_offset = std_offset;
            dst_offset.hour += 1;

            return .{ .{
                .standard = .{
                    .name = std_name,
                    .offset = std_offset,
                },
                .daylight_savings_time = .{
                    .name = dst_name,
                    .offset = dst_offset,
                },
            }, start };
        };
        start += i;

        // No rule, return
        if (start >= buf.len or buf[start] != ',') {
            return .{ .{
                .standard = .{
                    .name = std_name,
                    .offset = std_offset,
                },
                .daylight_savings_time = .{
                    .name = dst_name,
                    .offset = dst_offset,
                },
            }, start };
        }

        //  Read ','
        start += 1;

        // We have a rule, but no more characters, error
        if (start >= buf.len) return Error.InvalidTzString;

        break :blk dst_offset;
    };

    assert(start < buf.len);
    const start_date = blk: {
        const date, const i = try parseDate(buf[start..]);
        start += i;

        // We don't have an end yet, error
        if (start >= buf.len) return Error.InvalidTzString;

        break :blk date;
    };

    assert(start < buf.len);
    const start_time: Offset = blk: {
        if (buf[start] != '/') {
            break :blk .{ .hour = 2 };
        }
        start += 1;

        const time, const i = try parseOffset(buf[start..]);
        start += i;

        // We don't have an end yet, error
        if (start >= buf.len) return Error.InvalidTzString;

        break :blk time;
    };

    assert(start < buf.len);
    if (buf[start] != ',' or buf[start..].len < 2)
        return Error.InvalidTzString;
    start += 1;

    assert(start < buf.len);
    const end_date = blk: {
        const date, const i = try parseDate(buf[start..]);
        start += i;

        break :blk date;
    };

    const end_time: Offset = blk: {
        if (buf[start..].len == 0 or buf[start] != '/') {
            break :blk .{ .hour = 2 };
        }
        start += 1;

        const time, const i = try parseOffset(buf[start..]);
        start += i;

        break :blk time;
    };

    return .{ .{
        .standard = .{
            .name = std_name,
            .offset = std_offset,
        },
        .daylight_savings_time = .{
            .name = dst_name,
            .offset = dst_offset,
        },
        .rule = .{
            .start = .{
                .date = start_date,
                .offset = start_time,
            },
            .end = .{
                .date = end_date,
                .offset = end_time,
            },
        },
    }, start };
}

test parse {
    const caaf = std.testing.checkAllAllocationFailures;
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;
    const expectEqualString = std.testing.expectEqualStrings;
    const test_alloc = std.testing.allocator;

    const tst = struct {
        fn eql(a: TZString, b: TZString) !void {
            try expectEqualString(a.standard.name, b.standard.name);
            try expectEqual(a.standard.offset, b.standard.offset);

            try expect((a.daylight_savings_time == null) == (b.daylight_savings_time == null));

            if (a.daylight_savings_time != null) {
                const a_dst = a.daylight_savings_time.?;
                const b_dst = b.daylight_savings_time.?;

                try expectEqualString(a_dst.name, b_dst.name);
                try expectEqual(a_dst.offset, b_dst.offset);
            }

            try expectEqual(a.rule, b.rule);
        }

        pub fn tst(alloc: Allocator, expected: TZString, str: []const u8, end_char: ?u8) !void {
            const res, const end = try parse(alloc, str);
            defer res.deinit(alloc);

            try eql(expected, res);

            if (end_char) |e| {
                try expectEqual(e, str[end]);
            } else {
                try expectEqual(str.len, end);
            }
        }
    }.tst;

    // name: []const u8,
    // offset: Offset,
    try caaf(test_alloc, tst, .{
        TZString{
            .standard = .{
                .name = "CET",
                .offset = .{ .hour = -1 },
            },
        },
        "CET-1\n",
        '\n',
    });
    try caaf(test_alloc, tst, .{
        TZString{
            .standard = .{
                .name = "CET",
                .offset = .{ .hour = -1 },
            },
            .daylight_savings_time = .{
                .name = "CEST",
                .offset = .{ .hour = 0 },
            },
        },
        "CET-1CEST\n",
        '\n',
    });
    try caaf(test_alloc, tst, .{
        TZString{ .standard = .{
            .name = "CET",
            .offset = .{ .hour = -1 },
        }, .daylight_savings_time = .{
            .name = "CEST",
            .offset = .{ .hour = 0 },
        }, .rule = .{
            .start = .{
                .date = .{ .occurenceInMonth = .{
                    .month = .March,
                    .occurence = 5,
                    .day_of_week = DayOfWeek.from0(0).prev(),
                } },
                .offset = .{ .hour = 2 },
            },
            .end = .{
                .date = .{ .occurenceInMonth = .{
                    .month = .October,
                    .occurence = 5,
                    .day_of_week = DayOfWeek.from0(0).prev(),
                } },
                .offset = .{ .hour = 2 },
            },
        } },
        "CET-1CEST,M3.5.0,M10.5.0\n",
        '\n',
    });
    try caaf(test_alloc, tst, .{
        TZString{ .standard = .{
            .name = "CET",
            .offset = .{ .hour = -1 },
        }, .daylight_savings_time = .{
            .name = "CEST",
            .offset = .{ .hour = 0 },
        }, .rule = .{
            .start = .{
                .date = .{ .occurenceInMonth = .{
                    .month = .March,
                    .occurence = 5,
                    .day_of_week = DayOfWeek.from0(0).prev(),
                } },
                .offset = .{ .hour = 2, .minute = 4, .second = 20 },
            },
            .end = .{
                .date = .{ .occurenceInMonth = .{
                    .month = .October,
                    .occurence = 5,
                    .day_of_week = DayOfWeek.from0(0).prev(),
                } },
                .offset = .{ .hour = 3 },
            },
        } },
        "CET-1CEST,M3.5.0/2:4:20,M10.5.0/3\n",
        '\n',
    });

    try caaf(test_alloc, tst, .{
        TZString{ .standard = .{
            .name = "CET",
            .offset = .{ .hour = -1 },
        }, .daylight_savings_time = .{
            .name = "CEST",
            .offset = .{ .hour = 20 },
        }, .rule = .{
            .start = .{
                .date = .{ .zero_julian = 0 },
                .offset = .{ .hour = 2, .minute = 4, .second = 20 },
            },
            .end = .{
                .date = .{ .julian = 69 },
                .offset = .{ .hour = 3 },
            },
        } },
        "CET-1CEST+20,0/2:4:20,J69/3",
        null,
    });

    try caaf(test_alloc, tst, .{
        TZString{ .standard = .{
            .name = "+69CET",
            .offset = .{ .hour = -1 },
        }, .daylight_savings_time = .{
            .name = "-8CEST",
            .offset = .{ .hour = 20 },
        }, .rule = .{
            .start = .{
                .date = .{ .zero_julian = 0 },
                .offset = .{ .hour = 2, .minute = 4 },
            },
            .end = .{
                .date = .{ .julian = 69 },
                .offset = .{ .hour = 3, .minute = 59, .second = 59 },
            },
        } },
        "<+69CET>-1<-8CEST>+20,0/2:4,J69/3:59:59",
        null,
    });
}

const DateTime = @import("DateTime.zig");
const Year = DateTime.Year;
const MonthOfYear = DateTime.MonthOfYear;
const DayOfYear = DateTime.DayOfYear;
const DayOfWeek = DateTime.DayOfWeek;
const Hour = DateTime.Hour;
const Minute = DateTime.Minute;
const Second = DateTime.Second;
const TZString = @This();

const std = @import("std");

const assert = std.debug.assert;

const AnyReader = std.io.AnyReader;
const Allocator = std.mem.Allocator;
