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

const ParseNameError = Writer.Error || error{ ReadFailed, InvalidName, EmptyName };
fn parseName(r: *Reader, w: *Writer) ParseNameError!void {
    const state: enum { quoted, unquoted } = switch (r.peekByte() catch |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.EndOfStream => return error.EmptyName,
    }) {
        '<' => blk: {
            r.toss(1);
            break :blk .quoted;
        },
        'a'...'z',
        'A'...'Z',
        => .unquoted,
        else => return error.EmptyName,
    };

    while (r.peekByte()) |byte| switch (byte) {
        'a'...'z',
        'A'...'Z',
        => {
            r.toss(1);
            try w.writeByte(byte);
        },
        '0'...'9',
        '+',
        '-',
        => switch (state) {
            .unquoted => return,
            .quoted => {
                r.toss(1);
                try w.writeByte(byte);
            },
        },
        '>' => switch (state) {
            .unquoted => return error.InvalidName,
            .quoted => {
                r.toss(1);
                return;
            },
        },
        else => switch (state) {
            .quoted => return error.InvalidName,
            .unquoted => return,
        },
    } else |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.EndOfStream => switch (state) {
            .unquoted => return,
            .quoted => return error.InvalidName,
        },
    }
}

const ParseOffsetError = error{ ReadFailed, InvalidOffset, NoOffset };
fn parseOffset(r: *Reader) ParseOffsetError!Offset {
    const hour: i9 = blk: {
        const sign: enum { pos, neg } = switch (r.peekByte() catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.EndOfStream => return error.NoOffset,
        }) {
            '+' => sign: {
                r.toss(1);
                break :sign .pos;
            },

            '-' => sign: {
                r.toss(1);
                break :sign .neg;
            },
            '0'...'9' => .pos,
            else => return error.NoOffset,
        };

        var parsed_any = false;
        var hour: i9 = 0;
        while (r.peekByte()) |byte| switch (byte) {
            '0'...'9' => {
                parsed_any = true;
                hour = std.math.mul(i9, hour, 10) catch return error.InvalidOffset;
                hour += byte - '0';
                r.toss(1);
            },
            else => {
                if (!parsed_any) return error.InvalidOffset;
                if (hour > 167) return error.InvalidOffset;
                if (sign == .neg) hour = -hour;

                switch (byte) {
                    ':' => {
                        r.toss(1);
                        break :blk hour;
                    },
                    else => return .{ .hour = hour },
                }
            },
        } else |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.EndOfStream => {
                if (!parsed_any) return error.InvalidOffset;
                if (hour > 167) return error.InvalidOffset;
                if (sign == .neg) hour = -hour;
                return .{ .hour = hour };
            },
        }
    };

    const minute: u6 = blk: {
        var parsed_any = false;
        var minute: u6 = 0;
        while (r.peekByte()) |byte| switch (byte) {
            '0'...'9' => {
                parsed_any = true;
                minute = std.math.mul(u6, minute, 10) catch return error.InvalidOffset;
                minute += @intCast(byte - '0');
                r.toss(1);
            },
            else => {
                if (!parsed_any) return error.InvalidOffset;
                // TODO: leap seconds?
                if (minute >= 60) return error.InvalidOffset;

                switch (byte) {
                    ':' => {
                        r.toss(1);
                        break :blk minute;
                    },
                    else => return .{ .hour = hour, .minute = minute },
                }
            },
        } else |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.EndOfStream => {
                if (!parsed_any) return error.InvalidOffset;
                if (minute >= 60) return error.InvalidOffset;
                return .{ .hour = hour, .minute = minute };
            },
        }
    };

    var parsed_any = false;
    var second: u6 = 0;
    loop: while (r.peekByte()) |byte| switch (byte) {
        '0'...'9' => {
            parsed_any = true;
            second = std.math.mul(u6, second, 10) catch return error.InvalidOffset;
            second += @intCast(byte - '0');
            r.toss(1);
        },
        else => break :loop,
    } else |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.EndOfStream => {},
    }

    if (!parsed_any) return error.InvalidOffset;
    // TODO: leap seconds?
    if (second >= 60) return error.InvalidOffset;
    return .{ .hour = hour, .minute = minute, .second = second };
}

const ParseDateError = Reader.Error || error{InvalidDate};
fn parseDate(r: *Reader) ParseDateError!Rule.Date {
    const state: enum { julian, zero_julian, occurance_in_month } = switch (try r.peekByte()) {
        '0'...'9' => .zero_julian,
        'J' => blk: {
            r.toss(1);
            break :blk .julian;
        },
        'M' => blk: {
            r.toss(1);
            break :blk .occurance_in_month;
        },
        else => return error.InvalidDate,
    };

    switch (state) {
        .zero_julian => {
            var day: u9 = 0;
            while (r.peekByte()) |byte| switch (byte) {
                '0'...'9' => {
                    day = std.math.mul(u9, day, 10) catch return error.InvalidDate;
                    day += byte - '0';
                    r.toss(1);
                },
                else => {
                    if (day > 365) return error.InvalidDate;
                    return .{ .zero_julian = day };
                },
            } else |err| switch (err) {
                error.ReadFailed => return error.ReadFailed,
                error.EndOfStream => {
                    if (day > 365) return error.InvalidDate;
                    return .{ .zero_julian = day };
                },
            }
        },
        .julian => {
            var day: u9 = 0;
            while (r.peekByte()) |byte| switch (byte) {
                '0'...'9' => {
                    day = std.math.mul(u9, day, 10) catch return error.InvalidDate;
                    day += byte - '0';
                    r.toss(1);
                },
                else => {
                    if (365 < day or day < 1) return error.InvalidDate;
                    return .{ .julian = day };
                },
            } else |err| switch (err) {
                error.ReadFailed => return error.ReadFailed,
                error.EndOfStream => {
                    if (365 < day or day < 1) return error.InvalidDate;
                    return .{ .julian = day };
                },
            }
        },
        .occurance_in_month => {
            const month = month: {
                var month: u4 = 0;
                while (r.takeByte()) |byte| switch (byte) {
                    '0'...'9' => {
                        month = std.math.mul(u4, month, 10) catch return error.InvalidDate;
                        month += @intCast(byte - '0');
                    },
                    '.' => break :month MonthOfYear.fromChecked(month) catch
                        return error.InvalidDate,

                    else => return error.InvalidDate,
                } else |err| switch (err) {
                    error.ReadFailed => return error.ReadFailed,
                    error.EndOfStream => return error.InvalidDate,
                }
            };

            const occurence = occurence: {
                var occurence: u3 = 0;
                while (r.takeByte()) |byte| switch (byte) {
                    '0'...'7' => {
                        if (occurence != 0) return error.InvalidDate;
                        occurence = @intCast(byte - '0');
                    },
                    '.' => {
                        if (5 < occurence or occurence < 1) return error.InvalidDate;
                        break :occurence occurence;
                    },
                    else => return error.InvalidDate,
                } else |err| switch (err) {
                    error.ReadFailed => return error.ReadFailed,
                    error.EndOfStream => return error.InvalidDate,
                }
            };

            const day = day: {
                var day: u3 = 0;
                while (r.peekByte()) |byte| switch (byte) {
                    '0'...'7' => {
                        if (day != 0) return error.InvalidDate;
                        day = @intCast(byte - '0');
                        r.toss(1);
                    },
                    else => break :day (DayOfWeek.from0Checked(day) catch
                        return error.InvalidDate).prev(),
                } else |err| switch (err) {
                    error.ReadFailed => return error.ReadFailed,
                    error.EndOfStream => return error.InvalidDate,
                }
            };

            return .{ .occurenceInMonth = .{
                .month = month,
                .occurence = occurence,
                .day_of_week = day,
            } };
        },
    }
}

const ParseTzStringError = error{ReadFailed} || Allocator.Error || error{InvalidTzString};
pub fn parse(gpa: Allocator, r: *Reader) ParseTzStringError!TZString {
    const std_name = blk: {
        var aw: Writer.Allocating = .init(gpa);
        errdefer aw.deinit();

        parseName(r, &aw.writer) catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.WriteFailed => return error.OutOfMemory,
            error.EmptyName => {
                assert(aw.written().len == 0);
                break :blk "";
            },
            error.InvalidName => return error.InvalidTzString,
        };

        break :blk try aw.toOwnedSlice();
    };
    errdefer gpa.free(std_name);

    const std_offset = parseOffset(r) catch |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.NoOffset => return error.InvalidTzString,
        error.InvalidOffset => return error.InvalidTzString,
    };

    // If there is nothing left to parse (aka we see '\n' and or there is
    // litterally nothing left to parse) we should return here. Otherwise
    // dst_name and dst_offset get filled with no data
    switch (r.peekByte() catch |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.EndOfStream => '\n',
    }) {
        '\n' => return .{
            .standard = .{
                .name = std_name,
                .offset = std_offset,
            },
        },
        else => {},
    }

    const dst_name = blk: {
        var aw: Writer.Allocating = .init(gpa);
        errdefer aw.deinit();

        parseName(r, &aw.writer) catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.WriteFailed => return error.OutOfMemory,
            error.InvalidName => return error.InvalidTzString,
            error.EmptyName => {
                assert(aw.written().len == 0);
                break :blk "";
            },
        };

        break :blk try aw.toOwnedSlice();
    };
    errdefer gpa.free(dst_name);

    const dst_offset = blk: {
        if (',' == r.peekByte() catch |err| break :blk err) {
            // Ignore offset, continue on to rule
            var dst_offset = std_offset;
            dst_offset.hour += 1;

            break :blk dst_offset;
        }

        break :blk parseOffset(r);
    } catch |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.InvalidOffset => return error.InvalidTzString,
        error.EndOfStream,
        error.NoOffset,
        => {
            var dst_offset = std_offset;
            dst_offset.hour += 1;

            return .{
                .standard = .{
                    .name = std_name,
                    .offset = std_offset,
                },
                .daylight_savings_time = .{
                    .name = dst_name,
                    .offset = dst_offset,
                },
            };
        },
    };

    // No rule, return
    if (',' != r.peekByte() catch |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.EndOfStream => 0,
    }) {
        return .{
            .standard = .{
                .name = std_name,
                .offset = std_offset,
            },
            .daylight_savings_time = .{
                .name = dst_name,
                .offset = dst_offset,
            },
        };
    }

    //  Read ','
    assert(r.peekByte() catch unreachable == ',');
    r.toss(1);

    const start_date = parseDate(r) catch |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.EndOfStream => return error.InvalidTzString,
        error.InvalidDate => return error.InvalidTzString,
    };

    const start_time: Offset = blk: {
        if ('/' != r.peekByte() catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.EndOfStream => 0,
        }) break :blk .{ .hour = 2 };

        r.toss(1); // toss '/'

        break :blk parseOffset(r) catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.NoOffset => return error.InvalidTzString,
            error.InvalidOffset => return error.InvalidTzString,
        };
    };

    if (',' != r.takeByte() catch |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.EndOfStream => 0,
    }) return error.InvalidTzString;

    const end_date = parseDate(r) catch |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.EndOfStream => return error.InvalidTzString,
        error.InvalidDate => return error.InvalidTzString,
    };

    const end_time: Offset = blk: {
        if ('/' != r.peekByte() catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.EndOfStream => 0,
        }) break :blk .{ .hour = 2 };

        r.toss(1); // toss '/'

        break :blk parseOffset(r) catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.NoOffset => return error.InvalidTzString,
            error.InvalidOffset => return error.InvalidTzString,
        };
    };

    return .{
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
    };
}

// --- Testing ---
const expectEqual = std.testing.expectEqualDeep;
const expect = std.testing.expect;

const TestCase = struct {
    input: []const u8,
    fail: ?anyerror = null,
    tz_string: ?TZString = null,
    resolve: ?struct {
        year: Year,
        start: Rule.DateOffset.Resolved,
        end: Rule.DateOffset.Resolved,
    } = null,
};

fn tst(case: TestCase) !void {
    var input_reader: Reader = .fixed(case.input);

    const tz_string = TZString.parse(std.testing.allocator, &input_reader) catch |err| {
        if (case.fail) |expected_err| {
            try std.testing.expectEqual(expected_err, err);
            return;
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

    if (case.resolve) |resolve| {
        try expect(tz_string.rule != null);
        const rule = tz_string.rule.?;

        const start = rule.start.resolve(resolve.year);
        try expectEqual(resolve.start, start);

        const end = rule.end.resolve(resolve.year);
        try expectEqual(resolve.end, end);
    }
}

test "Happy path" {
    try tst(.{
        .tz_string = .{
            .standard = .{
                .name = "CET",
                .offset = .{ .hour = -1 },
            },
        },
        .input = "CET-1\n",
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

    try tst(.{
        .input = "A-167:59:59\n",
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
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "A-168",
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "A9999",
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "A-9999",
        .fail = error.InvalidTzString,
    });
}
test "empty designations" {
    try tst(.{
        .input = "-00-01",
        .tz_string = .{
            .standard = .{
                .name = "",
                .offset = .{ .hour = 0 },
            },
            .daylight_savings_time = .{
                .name = "",
                .offset = .{ .hour = -1 },
            },
        },
    });

    try tst(.{
        .input = "<>-00<>-01",
        .tz_string = .{
            .standard = .{
                .name = "",
                .offset = .{ .hour = 0 },
            },
            .daylight_savings_time = .{
                .name = "",
                .offset = .{ .hour = -1 },
            },
        },
    });
}
test "Out of bounds dates" {
    try tst(.{
        .input = "<>0<>0,J0,0",
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "<>0<>0,J366,0",
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "<>0<>0,366,0",
        .fail = error.InvalidTzString,
    });

    // Occurance in month months
    try tst(.{
        .input = "<>0<>0,M0.1.1,0",
        .fail = error.InvalidTzString,
    });
    try tst(.{
        .input = "<>0<>0,M13.1.1,0",
        .fail = error.InvalidTzString,
    });
    try tst(.{
        .input = "<>0<>0,M9999.1.1,0",
        .fail = error.InvalidTzString,
    });

    //  Occurance in month Occurance
    try tst(.{
        .input = "<>0<>0,M1.0.1,0",
        .fail = error.InvalidTzString,
    });
    try tst(.{
        .input = "<>0<>0,M1.6.1,0",
        .fail = error.InvalidTzString,
    });
    try tst(.{
        .input = "<>0<>0,M1.9999,0",
        .fail = error.InvalidTzString,
    });
    try tst(.{
        .input = "<>0<>0,M1.7777,0",
        .fail = error.InvalidTzString,
    });

    // Occurance in month days
    try tst(.{
        .input = "<>0<>0,M1.1.7,0",
        .fail = error.InvalidTzString,
    });
    try tst(.{
        .input = "<>0<>0,M1.1.9999,0",
        .fail = error.InvalidTzString,
    });
    try tst(.{
        .input = "<>0<>0,M1.1.7777,0",
        .fail = error.InvalidTzString,
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

test "incomplete offsets" {
    try tst(.{
        .input = "+",
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "-",
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "0:",
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "0:0:",
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "Hello-",
        .fail = error.InvalidTzString,
    });

    try tst(.{
        .input = "Hello+",
        .fail = error.InvalidTzString,
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
        .input = "<asdf",
        .fail = error.InvalidTzString,
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

const Io = std.Io;
const Reader = Io.Reader;
const Writer = Io.Writer;
const Allocator = std.mem.Allocator;
