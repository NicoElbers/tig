standard: Zone,
daylight_savings_time: ?Zone = null,
rule: ?Rule = null,

pub const Error = error{
    InvalidTzString,
} || Allocator.Error || std.fmt.ParseIntError || DayOfWeek.Error || MonthOfYear.Error;

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

/// TODO: I need to refactor this at some point because this is waaaay too much
/// code for what it's doing. I think I can simplify a lot by making it mostly
/// iterative with a couple of smaller state machines inside. This will probably
/// also greatly simplify the freeing logic.
///
/// TODO: Rework this so that either no character or an invalid character besides
/// '\n' can correctly terminate a TZ
pub fn parse(alloc: Allocator, r: AnyReader) Error!TZString {
    var state: union(enum) {
        start,

        std,

        std_quoted,
        std_quoted_end,

        std_offset_hour: struct { name: []const u8 },
        std_offset_minute: struct { std: Zone },
        std_offset_second: struct { std: Zone },

        dst: struct { std: Zone },

        dst_quoted: struct { std: Zone },
        dst_quoted_end: struct { std: Zone },

        dst_offset_hour: struct { std: Zone, dst: Zone },
        dst_offset_minute: struct { std: Zone, dst: Zone },
        dst_offset_second: struct { std: Zone, dst: Zone },

        date_start: struct { std: Zone, dst: Zone },

        date_start_julian: struct { std: Zone, dst: Zone },

        date_start_num: struct { std: Zone, dst: Zone },

        date_start_occurance_month: struct { std: Zone, dst: Zone },
        date_start_occurance_week: struct { std: Zone, dst: Zone, month: MonthOfYear },
        date_start_occurance_day: struct { std: Zone, dst: Zone, month: MonthOfYear, occurence: u3 },

        time_start_hour: struct { std: Zone, dst: Zone, start: Rule.DateOffset },
        time_start_minute: struct { std: Zone, dst: Zone, start: Rule.DateOffset },
        time_start_second: struct { std: Zone, dst: Zone, start: Rule.DateOffset },

        date_end: struct { std: Zone, dst: Zone, start: Rule.DateOffset },

        date_end_julian: struct { std: Zone, dst: Zone, start: Rule.DateOffset },

        date_end_num: struct { std: Zone, dst: Zone, start: Rule.DateOffset },

        date_end_occurance_month: struct { std: Zone, dst: Zone, start: Rule.DateOffset },
        date_end_occurance_week: struct { std: Zone, dst: Zone, start: Rule.DateOffset, month: MonthOfYear },
        date_end_occurance_day: struct { std: Zone, dst: Zone, start: Rule.DateOffset, month: MonthOfYear, occurence: u3 },

        time_end_hour: struct { std: Zone, dst: Zone, start: Rule.DateOffset, end: Rule.DateOffset },
        time_end_minute: struct { std: Zone, dst: Zone, start: Rule.DateOffset, end: Rule.DateOffset },
        time_end_second: struct { std: Zone, dst: Zone, start: Rule.DateOffset, end: Rule.DateOffset },
    } = .start;

    var scratch = std.ArrayList(u8).init(alloc);
    defer scratch.deinit();

    while (true) {
        const c = r.readByte() catch return Error.InvalidTzString;

        switch (state) {
            .start => switch (c) {
                '<' => state = .std_quoted,
                'a'...'z',
                'A'...'Z',
                => {
                    try scratch.append(c);
                    state = .std;
                },
                else => return Error.InvalidTzString,
            },

            .std => switch (c) {
                'a'...'z',
                'A'...'Z',
                => try scratch.append(c),
                '0'...'9',
                '-',
                '+',
                => {
                    const name = try scratch.toOwnedSlice();
                    errdefer alloc.free(name);

                    try scratch.append(c);
                    state = .{ .std_offset_hour = .{ .name = name } };
                },
                else => return Error.InvalidTzString,
            },

            .std_quoted => switch (c) {
                'a'...'z',
                'A'...'Z',
                '0'...'9',
                '+',
                '-',
                => try scratch.append(c),
                '>' => state = .std_quoted_end,
                else => return Error.InvalidTzString,
            },
            .std_quoted_end => switch (c) {
                '0'...'9',
                '+',
                '-',
                => {
                    const name = try scratch.toOwnedSlice();
                    errdefer alloc.free(name);

                    try scratch.append(c);
                    state = .{ .std_offset_hour = .{ .name = name } };
                },
                else => return Error.InvalidTzString,
            },

            .std_offset_hour => |s| switch (c) {
                '0'...'9' => try scratch.append(c),
                ':',
                '<',
                '\n',
                'a'...'z',
                'A'...'Z',
                => {
                    errdefer alloc.free(s.name);

                    const hour = try std.fmt.parseInt(i9, scratch.items, 10);
                    if (167 < hour or hour < -167) return Error.InvalidTzString;

                    scratch.clearRetainingCapacity();

                    const standard = Zone{
                        .name = s.name,
                        .offset = .{ .hour = hour },
                    };

                    switch (c) {
                        '<' => state = .{ .dst_quoted = .{ .std = standard } },
                        '\n' => return .{ .standard = standard },
                        ':' => state = .{ .std_offset_minute = .{ .std = standard } },
                        else => {
                            try scratch.append(c);

                            state = .{ .dst = .{ .std = standard } };
                        },
                    }
                },
                else => return Error.InvalidTzString,
            },

            .std_offset_minute => |s| switch (c) {
                '0'...'9' => try scratch.append(c),
                ':',
                '<',
                '\n',
                'a'...'z',
                'A'...'Z',
                => {
                    errdefer s.std.deinit(alloc);

                    const minute = try std.fmt.parseInt(u6, scratch.items, 10);
                    if (minute >= 60) return Error.InvalidTzString;

                    scratch.clearRetainingCapacity();

                    var standard = s.std;
                    standard.offset.minute = minute;

                    switch (c) {
                        '<' => state = .{ .dst_quoted = .{ .std = standard } },
                        '\n' => return .{ .standard = standard },
                        ':' => state = .{ .std_offset_second = .{ .std = standard } },
                        else => {
                            try scratch.append(c);

                            state = .{ .dst = .{ .std = standard } };
                        },
                    }
                },
                else => return Error.InvalidTzString,
            },

            .std_offset_second => |s| switch (c) {
                '0'...'9' => try scratch.append(c),
                '<',
                '\n',
                'a'...'z',
                'A'...'Z',
                => {
                    errdefer s.std.deinit(alloc);

                    const second = try std.fmt.parseInt(u6, scratch.items, 10);
                    if (second >= 60) return Error.InvalidTzString;

                    scratch.clearRetainingCapacity();

                    var standard = s.std;
                    standard.offset.second = second;

                    switch (c) {
                        '<' => state = .{ .dst_quoted = .{ .std = standard } },
                        '\n' => return .{ .standard = standard },
                        else => {
                            try scratch.append(c);
                            state = .{ .dst = .{ .std = standard } };
                        },
                    }
                },
                else => return Error.InvalidTzString,
            },

            .dst => |s| switch (c) {
                'a'...'z',
                'A'...'Z',
                => {
                    errdefer s.std.deinit(alloc);
                    try scratch.append(c);
                },
                '0'...'9',
                '-',
                '+',
                ',',
                '\n',
                => {
                    errdefer s.std.deinit(alloc);

                    const name = try scratch.toOwnedSlice();
                    errdefer alloc.free(name);

                    const dst: Zone = .{
                        .name = name,
                        .offset = .{ .hour = s.std.offset.hour + 1 },
                    };

                    switch (c) {
                        ',' => state = .{ .date_start = .{ .std = s.std, .dst = dst } },
                        '\n' => return .{ .standard = s.std, .daylight_savings_time = dst },
                        else => {
                            try scratch.append(c);
                            state = .{ .dst_offset_hour = .{ .std = s.std, .dst = dst } };
                        },
                    }
                },
                else => return Error.InvalidTzString,
            },

            .dst_quoted => |s| switch (c) {
                'a'...'z',
                'A'...'Z',
                '0'...'9',
                '+',
                '-',
                => {
                    errdefer s.std.deinit(alloc);
                    try scratch.append(c);
                },
                '>' => state = .{ .dst_quoted_end = .{ .std = s.std } },
                else => return Error.InvalidTzString,
            },
            .dst_quoted_end => |s| switch (c) {
                '0'...'9',
                '+',
                '-',
                ',',
                '\n',
                => {
                    errdefer s.std.deinit(alloc);

                    const name = try scratch.toOwnedSlice();
                    errdefer alloc.free(name);

                    var offset = s.std.offset;
                    offset.hour += 1;

                    const dst: Zone = .{
                        .name = name,
                        .offset = .{ .hour = s.std.offset.hour + 1 },
                    };

                    switch (c) {
                        ',' => state = .{ .date_start = .{ .std = s.std, .dst = dst } },
                        '\n' => return .{ .standard = s.std, .daylight_savings_time = dst },
                        else => {
                            try scratch.append(c);
                            state = .{ .dst_offset_hour = .{ .std = s.std, .dst = dst } };
                        },
                    }
                },
                else => return Error.InvalidTzString,
            },

            .dst_offset_hour => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                ':', ',', '\n' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const hour = try std.fmt.parseInt(i9, scratch.items, 10);
                    if (167 < hour or hour < -167) return Error.InvalidTzString;

                    scratch.clearRetainingCapacity();

                    var dst = s.dst;
                    dst.offset.hour = hour;

                    switch (c) {
                        ',' => state = .{ .date_start = .{ .std = s.std, .dst = dst } },
                        '\n' => return .{ .standard = s.std, .daylight_savings_time = dst },
                        ':' => state = .{ .dst_offset_minute = .{ .std = s.std, .dst = dst } },
                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .dst_offset_minute => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                ':', ',', '\n' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const minute = try std.fmt.parseInt(u6, scratch.items, 10);
                    if (minute >= 60) return Error.InvalidTzString;

                    scratch.clearRetainingCapacity();

                    var dst = s.dst;
                    dst.offset.minute = minute;

                    switch (c) {
                        ',' => state = .{ .date_start = .{ .std = s.std, .dst = dst } },
                        '\n' => return .{ .standard = s.std, .daylight_savings_time = dst },
                        ':' => state = .{ .dst_offset_second = .{ .std = s.std, .dst = dst } },
                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .dst_offset_second => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                ',', '\n' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const second = try std.fmt.parseInt(u6, scratch.items, 10);
                    if (second >= 60) return Error.InvalidTzString;

                    scratch.clearRetainingCapacity();

                    var dst = s.dst;
                    dst.offset.second = second;

                    switch (c) {
                        ',' => state = .{ .date_start = .{ .std = s.std, .dst = dst } },
                        '\n' => return .{ .standard = s.std, .daylight_savings_time = dst },
                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .date_start => |s| switch (c) {
                'J' => state = .{ .date_start_julian = .{ .std = s.std, .dst = s.dst } },
                'M' => state = .{ .date_start_occurance_month = .{ .std = s.std, .dst = s.dst } },
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    try scratch.append(c);
                    state = .{ .date_start_num = .{ .std = s.std, .dst = s.dst } };
                },
                else => return Error.InvalidTzString,
            },

            .date_start_julian => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                ',', '/' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const n = try std.fmt.parseInt(u9, scratch.items, 10);
                    scratch.clearRetainingCapacity();

                    if (365 < n or n < 1) return Error.InvalidTzString;

                    const start: Rule.DateOffset = .{
                        .date = .{ .julian = n },
                        .offset = .{ .hour = 2 },
                    };

                    switch (c) {
                        ',' => state = .{ .date_end = .{
                            .std = s.std,
                            .dst = s.dst,
                            .start = start,
                        } },

                        '/' => state = .{ .time_start_hour = .{
                            .std = s.std,
                            .dst = s.dst,
                            .start = start,
                        } },
                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .date_start_num => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                ',', '/' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const n = try std.fmt.parseInt(u9, scratch.items, 10);
                    scratch.clearRetainingCapacity();

                    if (n > 365) return Error.InvalidTzString;

                    const start: Rule.DateOffset = .{
                        .date = .{ .zero_julian = n },
                        .offset = .{ .hour = 2 },
                    };

                    switch (c) {
                        ',' => state = .{ .date_end = .{
                            .std = s.std,
                            .dst = s.dst,
                            .start = start,
                        } },

                        '/' => state = .{ .time_start_hour = .{
                            .std = s.std,
                            .dst = s.dst,
                            .start = start,
                        } },
                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .date_start_occurance_month => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                '.' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const n = try std.fmt.parseInt(u4, scratch.items, 10);
                    scratch.clearRetainingCapacity();

                    const month = MonthOfYear.from(n);

                    state = .{ .date_start_occurance_week = .{
                        .std = s.std,
                        .dst = s.dst,
                        .month = month,
                    } };
                },
                else => return Error.InvalidTzString,
            },

            .date_start_occurance_week => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                '.' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const occurance = try std.fmt.parseInt(u3, scratch.items, 10);
                    scratch.clearRetainingCapacity();

                    if (12 < occurance or occurance < 1) return Error.InvalidTzString;

                    state = .{ .date_start_occurance_day = .{
                        .std = s.std,
                        .dst = s.dst,
                        .month = s.month,
                        .occurence = occurance,
                    } };
                },
                else => return Error.InvalidTzString,
            },

            .date_start_occurance_day => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                '/', ',' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const n = try std.fmt.parseInt(u3, scratch.items, 10);
                    scratch.clearRetainingCapacity();

                    // We have to map day 0 to Sunday according to spec :(
                    const day = (try DayOfWeek.from0Checked(n)).prev();

                    const start: Rule.DateOffset = .{
                        .date = .{ .occurenceInMonth = .{
                            .month = s.month,
                            .occurence = s.occurence,
                            .day_of_week = day,
                        } },
                        .offset = .{ .hour = 2 },
                    };

                    switch (c) {
                        ',' => state = .{ .date_end = .{ .std = s.std, .dst = s.dst, .start = start } },
                        '/' => state = .{ .time_start_hour = .{ .std = s.std, .dst = s.dst, .start = start } },
                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .time_start_hour => |s| switch (c) {
                '0'...'9', '+', '-' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                ':', ',' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const slice = scratch.items;
                    defer scratch.clearRetainingCapacity();

                    const hour = try std.fmt.parseInt(i9, slice, 10);
                    if (167 < hour or hour < -167) return Error.InvalidTzString;

                    var start = s.start;
                    start.offset = .{ .hour = hour };

                    switch (c) {
                        ',' => state = .{ .date_end = .{ .std = s.std, .dst = s.dst, .start = start } },
                        ':' => state = .{ .time_start_minute = .{ .std = s.std, .dst = s.dst, .start = start } },
                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .time_start_minute => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                ':', ',' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const slice = scratch.items;
                    defer scratch.clearRetainingCapacity();

                    const minute = try std.fmt.parseInt(u6, slice, 10);
                    if (minute >= 60) return Error.InvalidTzString;

                    var start = s.start;
                    start.offset.minute = minute;

                    switch (c) {
                        ',' => state = .{ .date_end = .{ .std = s.std, .dst = s.dst, .start = start } },
                        ':' => state = .{ .time_start_second = .{ .std = s.std, .dst = s.dst, .start = start } },
                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .time_start_second => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                ',' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const slice = scratch.items;
                    defer scratch.clearRetainingCapacity();

                    const second = try std.fmt.parseInt(u6, slice, 10);
                    if (second >= 60) return Error.InvalidTzString;

                    var start = s.start;
                    start.offset.second = second;

                    state = .{ .date_end = .{ .std = s.std, .dst = s.dst, .start = start } };
                },
                else => return Error.InvalidTzString,
            },

            .date_end => |s| switch (c) {
                'J' => state = .{ .date_end_julian = .{ .std = s.std, .dst = s.dst, .start = s.start } },
                'M' => state = .{ .date_end_occurance_month = .{ .std = s.std, .dst = s.dst, .start = s.start } },
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                    state = .{ .date_end_num = .{ .std = s.std, .dst = s.dst, .start = s.start } };
                },
                else => return Error.InvalidTzString,
            },

            .date_end_julian => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                '\n', '/' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const n = try std.fmt.parseInt(u9, scratch.items, 10);
                    scratch.clearRetainingCapacity();

                    if (365 < n or n < 1) return Error.InvalidTzString;

                    const end: Rule.DateOffset = .{
                        .date = .{ .julian = n },
                        .offset = .{ .hour = 2 },
                    };

                    switch (c) {
                        '\n' => return .{
                            .standard = s.std,
                            .daylight_savings_time = s.dst,
                            .rule = .{
                                .start = s.start,
                                .end = end,
                            },
                        },

                        '/' => state = .{ .time_end_hour = .{
                            .std = s.std,
                            .dst = s.dst,
                            .start = s.start,
                            .end = end,
                        } },

                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .date_end_num => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                '\n', '/' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const slice = try scratch.toOwnedSlice();
                    const n = try std.fmt.parseInt(u9, slice, 10);

                    if (n > 365) return Error.InvalidTzString;

                    const end: Rule.DateOffset = .{
                        .date = .{ .zero_julian = n },
                        .offset = .{ .hour = 2 },
                    };

                    switch (c) {
                        '\n' => return .{
                            .standard = s.std,
                            .daylight_savings_time = s.dst,
                            .rule = .{
                                .start = s.start,
                                .end = end,
                            },
                        },

                        '/' => state = .{ .time_end_hour = .{
                            .std = s.std,
                            .dst = s.dst,
                            .start = s.start,
                            .end = end,
                        } },

                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .date_end_occurance_month => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                '.' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const n = try std.fmt.parseInt(u4, scratch.items, 10);
                    scratch.clearRetainingCapacity();

                    const month = MonthOfYear.from(n);

                    state = .{ .date_end_occurance_week = .{
                        .std = s.std,
                        .dst = s.dst,
                        .start = s.start,
                        .month = month,
                    } };
                },
                else => return Error.InvalidTzString,
            },

            .date_end_occurance_week => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                '.' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const occurence = try std.fmt.parseInt(u3, scratch.items, 10);
                    scratch.clearRetainingCapacity();

                    if (occurence > 5) return Error.InvalidTzString;

                    state = .{ .date_end_occurance_day = .{
                        .std = s.std,
                        .dst = s.dst,
                        .start = s.start,
                        .month = s.month,
                        .occurence = occurence,
                    } };
                },
                else => return Error.InvalidTzString,
            },

            .date_end_occurance_day => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                '/', '\n' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const n = try std.fmt.parseInt(u3, scratch.items, 10);
                    scratch.clearRetainingCapacity();

                    // We have to map day 0 to Sunday according to spec :(
                    const day = (try DayOfWeek.from0Checked(n)).prev();

                    const end: Rule.DateOffset = .{
                        .date = .{ .occurenceInMonth = .{
                            .month = s.month,
                            .occurence = s.occurence,
                            .day_of_week = day,
                        } },
                        .offset = .{ .hour = 2 },
                    };

                    switch (c) {
                        '\n' => return .{
                            .standard = s.std,
                            .daylight_savings_time = s.dst,
                            .rule = .{
                                .start = s.start,
                                .end = end,
                            },
                        },

                        '/' => state = .{ .time_end_hour = .{
                            .std = s.std,
                            .dst = s.dst,
                            .start = s.start,
                            .end = end,
                        } },

                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .time_end_hour => |s| switch (c) {
                '0'...'9', '+', '-' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                ':', '\n' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const slice = scratch.items;
                    defer scratch.clearRetainingCapacity();

                    const hour = try std.fmt.parseInt(i9, slice, 10);
                    if (167 < hour or hour < -167) return Error.InvalidTzString;

                    var end = s.end;
                    end.offset.hour = hour;

                    switch (c) {
                        '\n' => return .{
                            .standard = s.std,
                            .daylight_savings_time = s.dst,
                            .rule = .{
                                .start = s.start,
                                .end = end,
                            },
                        },

                        ':' => state = .{ .time_end_minute = .{
                            .std = s.std,
                            .dst = s.dst,
                            .start = s.start,
                            .end = end,
                        } },

                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .time_end_minute => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                ':', '\n' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const slice = scratch.items;
                    defer scratch.clearRetainingCapacity();

                    const minute = try std.fmt.parseInt(u6, slice, 10);
                    if (minute >= 60) return Error.InvalidTzString;

                    var end = s.end;
                    end.offset.minute = minute;

                    switch (c) {
                        '\n' => return .{
                            .standard = s.std,
                            .daylight_savings_time = s.dst,
                            .rule = .{
                                .start = s.start,
                                .end = end,
                            },
                        },

                        ':' => state = .{ .time_end_second = .{
                            .std = s.std,
                            .dst = s.dst,
                            .start = s.start,
                            .end = end,
                        } },
                        else => unreachable,
                    }
                },
                else => return Error.InvalidTzString,
            },

            .time_end_second => |s| switch (c) {
                '0'...'9' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);
                    try scratch.append(c);
                },
                '\n' => {
                    errdefer s.std.deinit(alloc);
                    errdefer s.dst.deinit(alloc);

                    const slice = scratch.items;
                    defer scratch.clearRetainingCapacity();

                    const second = try std.fmt.parseInt(u6, slice, 10);
                    if (second >= 60) return Error.InvalidTzString;

                    var end = s.end;
                    end.offset.second = second;

                    return .{
                        .standard = s.std,
                        .daylight_savings_time = s.dst,
                        .rule = .{
                            .start = s.start,
                            .end = end,
                        },
                    };
                },
                else => return Error.InvalidTzString,
            },
        }
    }

    unreachable;
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

        pub fn tst(alloc: Allocator, expected: TZString, str: []const u8) !void {
            var fbs = std.io.fixedBufferStream(str);
            const reader = fbs.reader().any();

            const res = try parse(alloc, reader);
            defer res.deinit(alloc);

            try eql(expected, res);
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
        "CET-1CEST+20,0/2:4:20,J69/3\n",
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
        "<+69CET>-1<-8CEST>+20,0/2:4,J69/3:59:59\n",
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
