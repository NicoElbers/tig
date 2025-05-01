//! Specification: https://pubs.opengroup.org/onlinepubs/9799919799/

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

        const Resolved = struct {
            doy: DayOfYear,
            hour: Hour,
            minute: Minute,
            second: Second,
        };

        /// Returns a type safe representation that notably does not include
        /// negative hours
        pub fn resolve(do: DateOffset, year: Year) Resolved {
            const offset = do.offset;

            const start_doy_num: i11 = do.date.toDayOfYear(year).to0();
            const days_in_year: i11 = year.getDaysInYear();

            const day_offset: i11, const hour_resolved: u5 = res: {
                // We want hour -1 to map to -1, so divFloor
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

            // Add days_in_year since start may be 0 and offset may be negative
            const resolved_doy: u9 = @intCast(
                @mod(days_in_year + start_doy_num + day_offset, days_in_year),
            );

            return .{
                .doy = DayOfYear.from0(resolved_doy, year.isLeapYear()),
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

                    const days_till_first_occurance = @mod(7 -
                        @as(u9, first_day_of_month.toOrdinal()) +
                        @as(u9, o.day_of_week.toOrdinal()), 7);

                    const days_till_occurance: u9 = blk: {
                        const days_till_occurance_guess = @as(u9, o.occurence - 1) * 7 +
                            days_till_first_occurance;

                        if (days_till_occurance_guess <= o.month.daysInMonth(is_leap_year))
                            break :blk days_till_occurance_guess;

                        // ... 5 means "the last d day in month m" which may occur in either
                        // the fourth or the fifth week).
                        //
                        // We extend this principle to "If the specified occurance falls
                        // outside of the month, get the last day d in month m" to deal
                        // with the potential case where someone tries to access day 42
                        // of February

                        const days_overflowed = days_till_occurance_guess -
                            o.month.daysInMonth(is_leap_year);

                        // we want to map:
                        // - 1 => 7 (1 / 7 + 1)
                        // - 7 => 7 (7 / 7 + 0)
                        // - 8 => 2 (8 / 7 + 1)
                        const weeks_overflowed = @divFloor(days_overflowed, 7) +
                            @intFromBool(@mod(days_overflowed, 7) != 0);

                        break :blk days_till_occurance_guess - 7 * weeks_overflowed;
                    };

                    return DayOfYear.from0(first_of_month + days_till_occurance, is_leap_year);
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
                '0'...'9' => {},
                ':' => {
                    const hour = std.fmt.parseInt(i9, buf[start..i], 10) catch return Error.InvalidOffset;
                    start = i + 1; // Skip :

                    if (hour < -167 or hour > 167) return Error.InvalidOffset;

                    break :blk hour;
                },
                '+',
                '-',
                => {
                    if (i == start) continue;

                    const hour = std.fmt.parseInt(i9, buf[start..i], 10) catch return Error.InvalidOffset;
                    start = i;

                    if (hour < -167 or hour > 167) return Error.InvalidOffset;

                    return .{ .{ .hour = hour }, start };
                },
                else => {
                    const hour = try std.fmt.parseInt(i9, buf[start..i], 10);
                    start = i;

                    if (hour < -167 or hour > 167) return Error.InvalidOffset;

                    return .{ .{ .hour = hour }, start };
                },
            }
        }

        const hour = std.fmt.parseInt(i9, buf[start..], 10) catch return Error.InvalidOffset;
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
                            const n = std.fmt.parseInt(u4, buf[start..i], 10) catch return Error.InvalidDate;
                            start = i + 1; // Skip the .

                            break :month MonthOfYear.fromChecked(n) catch return Error.InvalidDate;
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
                            const n = std.fmt.parseInt(u3, buf[start..i], 10) catch return Error.InvalidDate;
                            start = i;

                            break :day (DayOfWeek.from0Checked(n) catch return Error.InvalidDate).prev();
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

// --- Testing ---
const expectEqual = std.testing.expectEqualDeep;
const expect = std.testing.expect;

const TestCase = struct {
    input: []const u8,
    fail: ?anyerror = null,
    tz_string: ?TZString = null,
    end_idx: ?usize = null,
    resolve: ?struct {
        year: Year,
        start: Rule.DateOffset.Resolved,
        end: Rule.DateOffset.Resolved,
    } = null,
};
const tst = struct {
    pub fn tst(case: TestCase) !void {
        const tz_string, const end_idx = TZString.parse(std.testing.allocator, case.input) catch |err| {
            if (case.fail) |expected_err| {
                if (err == expected_err) return;
            }
            return err;
        };
        defer tz_string.deinit(std.testing.allocator);

        if (case.fail) |_| {
            return error.ExpectedFailure;
        }

        if (case.tz_string) |expected_string| {
            try expectEqual(expected_string, tz_string);
        }

        if (case.end_idx) |expected_end| {
            try expectEqual(expected_end, end_idx);
        }

        if (case.resolve) |resolve| {
            try expect(tz_string.rule != null);
            const rule = tz_string.rule.?;

            const start = rule.start.resolve(resolve.year);
            try expectEqual(resolve.start, start);

            const end = rule.end.resolve(resolve.year);
            try expectEqual(resolve.end, end);
        }
    }
}.tst;

test "Happy path" {
    try tst(.{
        .tz_string = .{
            .standard = .{
                .name = "CET",
                .offset = .{ .hour = -1 },
            },
        },
        .input = "CET-1\n",
        .end_idx = 5,
    });
    try tst(.{
        .tz_string = .{
            .standard = .{
                .name = "CET",
                .offset = .{ .hour = -1 },
            },
            .daylight_savings_time = .{
                .name = "CEST",
                .offset = .{ .hour = 0 },
            },
        },
        .input = "CET-1CEST\n",
        .end_idx = 9,
    });
    try tst(.{
        .tz_string = .{
            .standard = .{
                .name = "CET",
                .offset = .{ .hour = -1 },
            },
            .daylight_savings_time = .{
                .name = "CEST",
                .offset = .{ .hour = 0 },
            },
            .rule = .{
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
            },
        },
        .input = "CET-1CEST,M3.5.0,M10.5.0\n",
        .end_idx = 24,
    });
    try tst(.{
        .tz_string = .{
            .standard = .{
                .name = "CET",
                .offset = .{ .hour = -1 },
            },
            .daylight_savings_time = .{
                .name = "CEST",
                .offset = .{ .hour = 0 },
            },
            .rule = .{
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
            },
        },
        .input = "CET-1CEST,M3.5.0/2:4:20,M10.5.0/3\n",
        .end_idx = 33,
    });

    try tst(.{
        .tz_string = .{
            .standard = .{
                .name = "CET",
                .offset = .{ .hour = -1 },
            },
            .daylight_savings_time = .{
                .name = "CEST",
                .offset = .{ .hour = 20 },
            },
            .rule = .{
                .start = .{
                    .date = .{ .zero_julian = 0 },
                    .offset = .{ .hour = 2, .minute = 4, .second = 20 },
                },
                .end = .{
                    .date = .{ .julian = 69 },
                    .offset = .{ .hour = 3 },
                },
            },
        },
        .input = "CET-1CEST+20,0/2:4:20,J69/3",
        .end_idx = 27,
    });

    try tst(.{
        .tz_string = .{
            .standard = .{
                .name = "+69CET",
                .offset = .{ .hour = -1 },
            },
            .daylight_savings_time = .{
                .name = "-8CEST",
                .offset = .{ .hour = 20 },
            },
            .rule = .{
                .start = .{
                    .date = .{ .zero_julian = 0 },
                    .offset = .{ .hour = 2, .minute = 4 },
                },
                .end = .{
                    .date = .{ .julian = 69 },
                    .offset = .{ .hour = 3, .minute = 59, .second = 59 },
                },
            },
        },
        .input = "<+69CET>-1<-8CEST>+20,0/2:4,J69/3:59:59",
        .end_idx = 39,
    });
}

// Funky paths
test "Very long designation" {
    try tst(.{
        .input = "HelloWorld" ** 1000 ++ "Wow0",
        .tz_string = .{
            .standard = .{
                .name = "HelloWorld" ** 1000 ++ "Wow",
                .offset = .{ .hour = 0 },
            },
        },
    });
}

test "Very big offsets" {
    try tst(.{
        .input = "A167:59:59B0",
        .tz_string = .{
            .standard = .{
                .name = "A",
                .offset = .{ .hour = 167, .minute = 59, .second = 59 },
            },
            .daylight_savings_time = .{
                .name = "B",
                .offset = .{ .hour = 0 },
            },
        },
    });

    try tst(.{
        .input = "A-167:59:59",
        .tz_string = .{
            .standard = .{
                .name = "A",
                .offset = .{ .hour = -167, .minute = 59, .second = 59 },
            },
        },
    });
}

test "Invalid offsets" {
    try tst(.{
        .input = "A168",
        .fail = error.InvalidOffset,
    });

    try tst(.{
        .input = "A-168",
        .fail = error.InvalidOffset,
    });

    try tst(.{
        .input = "A9999",
        .fail = error.InvalidOffset,
    });

    try tst(.{
        .input = "A-9999",
        .fail = error.InvalidOffset,
    });
}
test "empty designations" {
    try tst(.{
        .input = "-00-00",
        .tz_string = .{
            .standard = .{
                .name = "",
                .offset = .{ .hour = 0 },
            },
            .daylight_savings_time = .{
                .name = "",
                .offset = .{ .hour = 0 },
            },
        },
    });

    try tst(.{
        .input = "<>-00<>-00",
        .tz_string = .{
            .standard = .{
                .name = "",
                .offset = .{ .hour = 0 },
            },
            .daylight_savings_time = .{
                .name = "",
                .offset = .{ .hour = 0 },
            },
        },
    });
}
test "Out of bounds dates" {
    try tst(.{
        .input = "<>0<>0,J0,0",
        .fail = error.InvalidDate,
    });

    try tst(.{
        .input = "<>0<>0,J366,0",
        .fail = error.InvalidDate,
    });

    try tst(.{
        .input = "<>0<>0,366,0",
        .fail = error.InvalidDate,
    });

    // Occurance in month months
    try tst(.{
        .input = "<>0<>0,M0.1.1,0",
        .fail = error.InvalidDate,
    });
    try tst(.{
        .input = "<>0<>0,M13.1.1,0",
        .fail = error.InvalidDate,
    });
    try tst(.{
        .input = "<>0<>0,M9999.1.1,0",
        .fail = error.InvalidDate,
    });

    //  Occurance in month Occurance
    try tst(.{
        .input = "<>0<>0,M1.0.1,0",
        .fail = error.InvalidDate,
    });
    try tst(.{
        .input = "<>0<>0,M1.6.1,0",
        .fail = error.InvalidDate,
    });
    try tst(.{
        .input = "<>0<>0,M1.9999,0",
        .fail = error.InvalidDate,
    });

    // Occurance in month days
    try tst(.{
        .input = "<>0<>0,M1.1.7,0",
        .fail = error.InvalidDate,
    });
    try tst(.{
        .input = "<>0<>0,M1.1.9999,0",
        .fail = error.InvalidDate,
    });
}

test "Out of bounds occurance in month" {
    // Taken from Europe/Amsterdam
    // October 2024 did not have 5 Sundays

    // The 5th Sunday of March in 2024 was March 31st
    const march_31 = DateTime.build(.{ .year = 2024, .month = .March, .day_of_month = 31 });

    // The would be 5th sunday of October is November 3rd, but this maps to
    // October 27th according to spec
    const october_27 = DateTime.build(.{ .year = 2024, .month = .October, .day_of_month = 27 });

    try tst(.{
        .input = "CET-1CEST,M3.5.0,M10.5.0/3",
        .resolve = .{
            .year = Year.from(2024),
            .start = .{
                .doy = march_31.getDayOfYear(),
                .hour = Hour.from(2),
                .minute = Minute.from(0),
                .second = Second.from(0),
            },
            .end = .{
                .doy = october_27.getDayOfYear(),
                .hour = Hour.from(3),
                .minute = Minute.from(0),
                .second = Second.from(0),
            },
        },
    });
}

test "Out of year occurance in month" {
    // Artificial example

    // In 2024, there are only 4 saturdays
    const december_28 = DateTime.build(.{ .year = 2024, .month = .December, .day_of_month = 28 });

    try tst(.{
        .input = "<>-1<>,M12.5.6,0",
        .resolve = .{
            .year = Year.from(2024),
            .start = .{
                .doy = december_28.getDayOfYear(),
                .hour = Hour.from(2),
                .minute = Minute.from(0),
                .second = Second.from(0),
            },
            .end = .{
                .doy = DayOfYear.from0(0, true),
                .hour = Hour.from(2),
                .minute = Minute.from(0),
                .second = Second.from(0),
            },
        },
    });
}

test "Very big rule offsets" {
    // Artificial examples

    const december_31_24 = DateTime.build(.{ .year = 2024, .month = .December, .day_of_month = 31 });
    const january_1_26 = DateTime.build(.{ .year = 2026, .month = .January, .day_of_month = 1 });
    try tst(.{
        .input = "<>0<>0,0/-1,J365/25",
        .resolve = .{
            .year = Year.from(2024),
            .start = .{
                .doy = december_31_24.getDayOfYear(),
                .hour = Hour.from(23),
                .minute = Minute.from(0),
                .second = Second.from(0),
            },
            .end = .{
                .doy = january_1_26.getDayOfYear(),
                .hour = Hour.from(1),
                .minute = Minute.from(0),
                .second = Second.from(0),
            },
        },
    });

    // 167 hours == 6 days and 23 hours
    const december_25_24 = DateTime.build(.{ .year = 2024, .month = .December, .day_of_month = 25 });
    const january_6_26 = DateTime.build(.{ .year = 2026, .month = .January, .day_of_month = 6 });

    try tst(.{
        .input = "<>0<>0,0/-167:59:59,J365/167:59:59",
        .resolve = .{
            .year = Year.from(2024),
            .start = .{
                .doy = december_25_24.getDayOfYear(),
                .hour = Hour.from(1),
                .minute = Minute.from(59),
                .second = Second.from(59),
            },
            .end = .{
                .doy = january_6_26.getDayOfYear(),
                .hour = Hour.from(23),
                .minute = Minute.from(59),
                .second = Second.from(59),
            },
        },
    });
}

test "incomplete strings" {
    try tst(.{
        .input = "",
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "Hello",
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "+",
        .fail = error.InvalidOffset,
    });

    try tst(.{
        .input = "-",
        .fail = error.InvalidOffset,
    });

    try tst(.{
        .input = "Hello-",
        .fail = error.InvalidOffset,
    });

    try tst(.{
        .input = "Hello+",
        .fail = error.InvalidOffset,
    });
}

test {
    // Compile errors
    _ = &parse;
    _ = &deinit;
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
