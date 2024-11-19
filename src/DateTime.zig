//! A date and time representation based on ISO 8600-1:2019 representing only UTC.
//! Other timezones are represented through {TIMEZONE_WRAPPER}
//! TODO: Add timezone wrapper; see todo.md
//!
//! This implementation can represent dates from
//!     -292277024627-01-26T08:29:52Z to (-292 billion)
//!      292277024626-12-05T15:30:07Z    ( 292 billion)
//!
//! TODO: I actually will support leap seconds
//!
//! This representation explicitly ignores leap seconds, as they are
//! 1) not regularly specified but instead assigned by the IERS,
//! 2) not accounted for in many computer systems and,
//! 3) scheduled to be abandoned by or before 2035
//!    (https://en.m.wikipedia.org/wiki/Leap_second)
//!
//! This means that dates represented here after 2016-12-31 are off by
//! 27 seconds from the standard and 37 seconds off TAI. If you need a
//! leap second accurate date, please refer to the {TIMEZONE_WRAPPER}
//! TODO: Make leap second wrapper; See todo.md

/// Amount of seconds after gregorian date 0000-01-01T00:00Z, or in other words
/// year 0, January 1st at the first instant of the day.
///
/// If the represented date is before the gregorian year 0, the timestamp is
/// negative.
///
/// Do note that gregorian year 0 corresponds to 1BC.
/// source: https://en.m.wikipedia.org/wiki/Year_zero
timestamp: i64,

// FIXME: Negative years are broken asf. pls fix

pub const gregorianEpoch: DateTime = .{ .timestamp = 0 };
pub const unixEpoch: DateTime = .{ .timestamp = 62_167_219_200 };

/// Type safe representation of a year, centered around the year 0
/// of the gregorian calendar
///
/// To obtain a `Year` it's reccomended to use `Year.from` as that does some
/// aditional bounds checks
pub const Year = enum(i40) {
    _,

    /// Average seconds per year ignoring leap seconds, but including leap years
    ///
    /// source: https://sibenotes.com/maths/how-many-seconds-are-in-a-year/
    /// Additionally verified
    pub const avg_s_per_y = 31_556_952;

    const min = Year.fromUnchecked(-292277024627);
    const max = Year.fromUnchecked(292277024626);

    test "min/max" {
        const expectEqual = std.testing.expectEqual;

        try expectEqual((DateTime{ .timestamp = minInt(i64) }).getYear(), min);
        try expectEqual((DateTime{ .timestamp = maxInt(i64) }).getYear(), max);
    }

    pub const Error = error{UnrepresentableYear};

    /// Convert any integer type to a type safe year.
    ///
    /// This function assumes that the year you provide is valid, and representable
    /// by the `DateTime` timestamp
    pub fn from(year: anytype) Year {
        const year_cast: i40 = @intCast(year);

        assert(year_cast >= min.to());
        assert(year_cast <= max.to());

        return fromUnchecked(year_cast);
    }

    /// Convert any integer type to a type safe year.
    ///
    /// If the year cannot be represented by the `DateTime` timestamp, this
    /// function returns `UnrepresetableYear`. This only happes for years more
    /// than ~292 billion years removed from year 0.
    pub fn fromChecked(year: anytype) Error!Year {
        const year_cast: i40 = cast(i40, year) orelse
            return Error.UnrepresentableYear;

        if (year_cast < min.to()) return Error.UnrepresentableYear;
        if (year_cast > max.to()) return Error.UnrepresentableYear;

        return fromUnchecked(year_cast);
    }

    fn fromUnchecked(year: i40) Year {
        return @enumFromInt(year);
    }

    test from {
        const expectEqual = std.testing.expectEqual;

        try expectEqual(123, Year.from(123).to());
        try expectEqual(-123, Year.from(@as(i32, -123)).to());
        try expectEqual(1000, Year.from(@as(u128, 1000)).to());
        try expectEqual(0, Year.from(@as(u0, 0)).to());

        try expectEqual(min, Year.from(@as(i180, min.to())));
        try expectEqual(max, Year.from(@as(i180, max.to())));
    }

    test fromChecked {
        const expectError = std.testing.expectError;
        const expectEqual = std.testing.expectEqual;

        try expectEqual(123, Year.from(123).to());
        try expectEqual(-123, Year.from(@as(i32, -123)).to());
        try expectEqual(1000, Year.from(@as(u128, 1000)).to());
        try expectEqual(0, Year.from(@as(u0, 0)).to());

        try expectEqual(min, Year.from(@as(i180, min.to())));
        try expectEqual(max, Year.from(@as(i180, max.to())));

        try expectError(Error.UnrepresentableYear, Year.fromChecked(max.to() + 1));
        try expectError(Error.UnrepresentableYear, Year.fromChecked(min.to() - 1));

        try expectError(Error.UnrepresentableYear, Year.fromChecked(maxInt(i40)));
        try expectError(Error.UnrepresentableYear, Year.fromChecked(minInt(i40)));
    }

    pub fn to(year: Year) i40 {
        assert(year.isValid());

        return toUnchecked(year);
    }

    pub fn toChecked(year: Year) Error!i40 {
        if (!year.isValid())
            return Error.UnrepresetableYear;

        return toUnchecked(year);
    }

    fn toUnchecked(year: Year) i40 {
        return @intFromEnum(year);
    }

    pub fn isValid(year: Year) bool {
        return year.toUnchecked() >= min.toUnchecked() and
            year.toUnchecked() <= max.toUnchecked();
    }

    test isValid {
        const expectEqual = std.testing.expectEqual;

        try expectEqual(true, isValid(Year.from(0)));
        try expectEqual(true, isValid(min));
        try expectEqual(true, isValid(max));

        try expectEqual(false, isValid(Year.fromUnchecked(max.to() + 1)));
        try expectEqual(false, isValid(Year.fromUnchecked(min.to() - 1)));

        try expectEqual(false, isValid(Year.fromUnchecked(maxInt(i40))));
        try expectEqual(false, isValid(Year.fromUnchecked(minInt(i40))));
    }

    pub fn getDaysInYear(year: Year) u9 {
        return 365 + @as(u9, @intCast(@intFromBool(year.isLeapYear())));
    }

    pub fn isLeapYear(year: Year) bool {
        const year_int = year.to();

        return @mod(year_int, 400) == 0 or
            (@mod(year_int, 4) == 0 and @mod(year_int, 100) != 0);
    }

    test isLeapYear {
        const expectEqual = std.testing.expectEqual;

        try expectEqual(true, isLeapYear(Year.from(0)));

        try expectEqual(false, isLeapYear(Year.from(1)));
        try expectEqual(false, isLeapYear(Year.from(2)));
        try expectEqual(false, isLeapYear(Year.from(3)));
        try expectEqual(true, isLeapYear(Year.from(4)));

        try expectEqual(false, isLeapYear(Year.from(5)));
        try expectEqual(false, isLeapYear(Year.from(6)));
        try expectEqual(false, isLeapYear(Year.from(7)));
        try expectEqual(true, isLeapYear(Year.from(8)));

        try expectEqual(false, isLeapYear(Year.from(99)));
        try expectEqual(false, isLeapYear(Year.from(100)));
        try expectEqual(false, isLeapYear(Year.from(101)));

        try expectEqual(false, isLeapYear(Year.from(-99)));
        try expectEqual(false, isLeapYear(Year.from(-100)));
        try expectEqual(false, isLeapYear(Year.from(-101)));

        try expectEqual(false, isLeapYear(Year.from(399)));
        try expectEqual(true, isLeapYear(Year.from(400)));
        try expectEqual(false, isLeapYear(Year.from(401)));

        // Leap years are symetric around year 0
        for (0..10_000) |i| {
            const year_pos = Year.from(i);
            const year_neg = Year.from(i);

            try expectEqual(year_pos.isLeapYear(), year_neg.isLeapYear());
        }
    }

    /// The amount of leap years before and including the current year and year
    /// 0.
    pub fn leapYearsSinceGregorianEpoch(year: Year) i40 {
        var year_int: i40 = @intCast(@abs(year.to()));

        const leap_400 = 97;
        const cycle_400 = @divTrunc(year_int, 400);
        year_int = @rem(year_int, 400);

        const leap_100 = 24;
        const cycle_100 = @divTrunc(year_int, 100);
        year_int = @rem(year_int, 100);

        const leap_4 = 1;
        const cycle_4 = @divTrunc(year_int, 4);

        const sum = cycle_400 * leap_400 +
            cycle_100 * leap_100 +
            cycle_4 * leap_4 + 1;

        return if (year.to() >= 0)
            sum
        else
            -sum + 1;
    }

    test leapYearsSinceGregorianEpoch {
        const expectEqual = std.testing.expectEqual;

        try expectEqual(1, leapYearsSinceGregorianEpoch(Year.from(0)));
        try expectEqual(0, leapYearsSinceGregorianEpoch(Year.from(-1)));
        try expectEqual(0, leapYearsSinceGregorianEpoch(Year.from(-2)));
        try expectEqual(0, leapYearsSinceGregorianEpoch(Year.from(-3)));
        try expectEqual(-1, leapYearsSinceGregorianEpoch(Year.from(-4)));

        // Test cycles (+ 1 due to year 0 being a leap year)
        try expectEqual(2, leapYearsSinceGregorianEpoch(Year.from(4)));
        try expectEqual(25, leapYearsSinceGregorianEpoch(Year.from(100)));
        try expectEqual(98, leapYearsSinceGregorianEpoch(Year.from(400)));

        try expectEqual(-1, leapYearsSinceGregorianEpoch(Year.from(-4)));
        try expectEqual(-24, leapYearsSinceGregorianEpoch(Year.from(-100)));
        try expectEqual(-97, leapYearsSinceGregorianEpoch(Year.from(-400)));

        var found_leap_years: i32 = 0;
        for (0..10_000) |i| {
            const year_pos: Year = Year.from(i);
            const year_neg: Year = Year.from(i);

            try expectEqual(year_pos.isLeapYear(), year_neg.isLeapYear());

            if (year_neg.isLeapYear()) found_leap_years += 1;

            try expectEqual(found_leap_years, leapYearsSinceGregorianEpoch(year_pos));
            try expectEqual(found_leap_years, leapYearsSinceGregorianEpoch(year_neg));
        }
    }

    /// The amount of days between January 1st of year 0, and January 1st of `year`
    ///
    /// Does not include the last day, so for year 1, this would be 366 days,
    /// as year 0 is a leap year.
    pub fn daysSinceGregorianEpoch(year: Year) i64 {
        const year_int: i64 = year.to();

        return if (year_int >= 0)
            year_int * 365 + leapYearsSinceGregorianEpoch(year) - @intFromBool(isLeapYear(year))
        else
            year_int * 365 + leapYearsSinceGregorianEpoch(year);
    }

    test daysSinceGregorianEpoch {
        const expectEqual = std.testing.expectEqual;

        try expectEqual(0, daysSinceGregorianEpoch(Year.from(0)));
        try expectEqual(366, daysSinceGregorianEpoch(Year.from(1)));
        try expectEqual(-365, daysSinceGregorianEpoch(Year.from(-1)));

        const tst = struct {
            pub fn tst(day: i64, year: i40) !void {
                const year_pos = Year.from(year);
                const year_neg = Year.from(-year);

                try expectEqual(day, daysSinceGregorianEpoch(year_pos));

                // We are supposed to add 1 to cancel out the fact that year 0
                // is a leap year
                //
                // We also count the leap day in a leap year
                try expectEqual(-day + 1 - @intFromBool(year_neg.isLeapYear()), daysSinceGregorianEpoch(year_neg));
            }
        }.tst;

        // Near zero
        try tst(366 * 1 + 365 * 0, 1);
        try tst(366 * 1 + 365 * 1, 2);
        try tst(366 * 1 + 365 * 2, 3);
        try tst(366 * 1 + 365 * 3, 4);
        try tst(366 * 2 + 365 * 3, 5);

        // Around centennial year
        try tst(36_160, 99);
        try tst(36_525, 100);
        try tst(36_890, 101);

        // Around centennial year divisible by 400
        try tst(145_732, 399);
        try tst(146_097, 400);
        try tst(146_463, 401);

        // Modern years
        try tst(719_528, 1970);
        try tst(730_485, 2000);
        try tst(739_251, 2024);
    }

    /// day is the amount of days since gregorian 0000-01-01T00:00Z
    pub fn fromCalendarDay(day: Day) Year {
        // zig fmt: off
        // Leap years can be thought of as 4 different cycles, 
        // 1) a 400 year cycle which starts and ends in a centennial year divisible by 400, 
        // 2) a 100 year cycle which starts and ends in a centennial year not divisible by 400
        // 3) a   4 year cycle which starts and ends in a regular leap year
        // 4) a   1 year cycle which starts and ends in a regular year
        const d_in_cycle_400 = 366 * 97 + 365 * 303;
        const d_in_cycle_100 = 366 * 24 + 365 *  76;
        const d_in_cycle_4   = 366 *  1 + 365 *   3;
        const d_in_cycle_1   = 366 *  0 + 365 *   1;
        // zig fmt: on

        // Calendar day to ordinal day
        var days_left = day.toOrdinal();

        // Correct for the fact that year 0 is a leap year
        days_left -= @intFromBool(days_left > 0);

        const cycle_400 = @divTrunc(days_left, d_in_cycle_400);
        days_left = @rem(days_left, d_in_cycle_400);

        const cycle_100 = @divTrunc(days_left, d_in_cycle_100);
        days_left = @rem(days_left, d_in_cycle_100);

        const cycle_4 = @divTrunc(days_left, d_in_cycle_4);
        days_left = @rem(days_left, d_in_cycle_4);

        const cycle_1 = @divTrunc(days_left, d_in_cycle_1);

        return Year.from(cycle_400 * 400 +
            cycle_100 * 100 +
            cycle_4 * 4 +
            cycle_1 -
            // TODO: Investigate this line, it's sus
            @as(i64, @intFromBool(days_left < 0)));
    }

    test fromCalendarDay {
        const expectEqual = std.testing.expectEqual;

        const tst = struct {
            pub fn tst(ordinal_day: i64, year: i40) !void {
                const year_pos = Year.from(year);

                for (0..365) |shift| {
                    const shifted_day = ordinal_day + @as(i64, @intCast(shift));

                    const calendar_day_pos = Day.fromOrdinalDay(shifted_day);

                    try expectEqual(year_pos, fromCalendarDay(calendar_day_pos));
                }

                if (year_pos.isLeapYear()) {
                    const shift = 365;
                    const shifted_day = ordinal_day + shift;

                    const calendar_day_pos = Day.fromOrdinalDay(shifted_day);

                    try expectEqual(year_pos, fromCalendarDay(calendar_day_pos));
                }
            }
        }.tst;

        // Near zero
        try tst(0, 0);
        try tst(366 * 1 + 365 * 0, 1);
        try tst(366 * 1 + 365 * 1, 2);
        try tst(366 * 1 + 365 * 2, 3);
        try tst(366 * 1 + 365 * 3, 4);
        try tst(366 * 2 + 365 * 3, 5);

        // Around centennial year
        try tst(36_160, 99);
        try tst(36_525, 100);
        try tst(36_890, 101);

        // Around centennial year divisible by 400
        try tst(145_732, 399);
        try tst(146_097, 400);
        try tst(146_463, 401);

        // Modern years
        try tst(719_528, 1970);
        try tst(730_485, 2000);
        try tst(739_251, 2024);
    }

    pub fn firstDayOfWeekOfYear(year: Year) DayOfWeek {
        // Year 0 starts on a Saturday, after that every non leap year
        // starts one day later (Monday -> Tuesday) and every leap year
        // starts two days later (Monday -> Wednesday)
        // Verified through `date`

        const days_moved: i40 = year.to() +
            year.leapYearsSinceGregorianEpoch() -
            @intFromBool(year.isLeapYear()) + // Jan 1 is always before feb 29
            DayOfWeek.Saturday.toOrdinal(); // Start on saturday :(

        const week_days_moved: u3 = @intCast(@mod(days_moved, 7));
        return DayOfWeek.fromOrdinal(week_days_moved);
    }

    test firstDayOfWeekOfYear {
        const expectEqual = std.testing.expectEqual;

        try expectEqual(.Saturday, Year.from(0).firstDayOfWeekOfYear());
        try expectEqual(.Monday, Year.from(1).firstDayOfWeekOfYear());
        try expectEqual(.Tuesday, Year.from(2).firstDayOfWeekOfYear());
        try expectEqual(.Wednesday, Year.from(3).firstDayOfWeekOfYear());
        try expectEqual(.Thursday, Year.from(4).firstDayOfWeekOfYear());
        try expectEqual(.Saturday, Year.from(5).firstDayOfWeekOfYear());
        try expectEqual(.Sunday, Year.from(6).firstDayOfWeekOfYear());
        try expectEqual(.Monday, Year.from(7).firstDayOfWeekOfYear());

        try expectEqual(.Thursday, Year.from(1970).firstDayOfWeekOfYear());
        try expectEqual(.Saturday, Year.from(2000).firstDayOfWeekOfYear());
        try expectEqual(.Monday, Year.from(2024).firstDayOfWeekOfYear());

        // These are honestly just guesses, they are primarily tested so that
        // I am sure the function won't crash
        try expectEqual(.Friday, min.firstDayOfWeekOfYear());
        try expectEqual(.Sunday, max.firstDayOfWeekOfYear());
    }

    pub fn weeksInYear(year: Year) u6 {
        // For a year to contain 53 weeks, it must:
        // - Have its first day be before or on a Thursday;
        // - Have its last day be after or on a Thursday;
        //
        // Important facts:
        // - A non leap year has 52 weeks and 1 day;
        // - A leap year has 52 weeks and 2 days;
        // - A week is contained in a year, if the Thursday of that week is
        //   in the year;

        return switch (year.firstDayOfWeekOfYear()) {
            .Tuesday => 52 + year.isLeapYear(),
            .Wednesday => 53,
            else => 52,
        };
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.to(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            // Effectively a copy of std.fmt.formatInt, but I wanted a little
            // bit of custom logic with the sign so we ball

            const int_value = value.to();

            const value_info = @typeInfo(@TypeOf(int_value)).int;

            // The type must have the same size as `base` or be wider in order for the
            // division to work
            const min_int_bits = comptime @max(value_info.bits, 8);
            const MinInt = std.meta.Int(.unsigned, min_int_bits);

            const abs_value = @abs(int_value);
            // The worst case in terms of space needed is base 2, plus 1 for the sign
            var buf: [1 + @max(@as(comptime_int, value_info.bits), 1)]u8 = undefined;

            var a: MinInt = abs_value;
            var index: usize = buf.len;

            while (a >= 100) : (a = @divTrunc(a, 100)) {
                index -= 2;
                buf[index..][0..2].* = std.fmt.digits2(@intCast(a % 100));
            }

            if (a < 10) {
                index -= 1;
                buf[index] = '0' + @as(u8, @intCast(a));
            } else {
                index -= 2;
                buf[index..][0..2].* = std.fmt.digits2(@intCast(a));
            }

            while (index > buf.len - 4) {
                index -= 1;
                buf[index] = '0';
            }

            if (int_value < 0) {
                // Negative integer
                index -= 1;
                buf[index] = '-';
            }

            try writer.writeAll(buf[index..]);
        }
    }
};

pub const Month = enum(i48) {
    _,
};

pub const MonthOfYear = enum(u4) {
    // zig fmt: off
    January   =  1,
    February  =  2,
    March     =  3,
    April     =  4,
    May       =  5,
    June      =  6,
    July      =  7,
    August    =  8,
    September =  9,
    October   = 10,
    November  = 11,
    December  = 12,
    // zig fmt: on

    pub const Error = error{ UnrepresentableDay, UnrepresentableMonth };

    pub fn fromMonthNumber(month: anytype) MonthOfYear {
        const month_cast: u4 = @intCast(month);

        assert(month_cast >= 1);
        assert(month_cast <= 12);

        return fromMonthNumberUnchecked(month_cast);
    }

    pub fn fromMonthNumberChecked(month: anytype) Error!MonthOfYear {
        const month_cast = std.math.cast(u4, month) catch
            return Error.UnrepresentableDay;

        if (month_cast < 0 or month_cast > 11)
            return Error.UnrepresentableMonth;

        return fromMonthNumberUnchecked(month_cast);
    }

    pub fn fromOrdinal(month: anytype) MonthOfYear {
        return fromMonthNumber(month + 1);
    }

    pub fn fromOrdinalChecked(month: anytype) MonthOfYear {
        return fromMonthNumberChecked(month + 1);
    }

    fn fromMonthNumberUnchecked(month: u4) MonthOfYear {
        return @enumFromInt(month);
    }

    pub fn toOrdinal(month: MonthOfYear) u4 {
        return toMonthNumber(month) - 1;
    }

    pub fn toMonthNumber(month: MonthOfYear) u4 {
        return @intFromEnum(month);
    }

    // pub fn fromOrdinal(ordinal_month: u4) Error!Month {
    //     if (ordinal_month < 0 or ordinal_month > 11)
    //         return Error.UnrepresentableMonth;
    //
    //     return @enumFromInt(ordinal_month + 1);
    // }

    pub fn next(month: MonthOfYear) MonthOfYear {
        return switch (month) {
            // zig fmt: off
            .January   => .February,
            .February  => .March,
            .March     => .April,
            .April     => .May,
            .May       => .June,
            .June      => .July,
            .July      => .August,
            .August    => .September,
            .September => .October,
            .October   => .November,
            .November  => .December,
            .December  => .January,
            // zig fmt: on
        };
    }

    pub fn prev(month: MonthOfYear) MonthOfYear {
        return switch (month) {
            // zig fmt: off
            .January   => .December,
            .February  => .January,
            .March     => .February,
            .April     => .March,
            .May       => .April,
            .June      => .May,
            .July      => .June,
            .August    => .July,
            .September => .August,
            .October   => .September,
            .November  => .October,
            .December  => .November,
            // zig fmt: on
        };
    }

    pub fn daysInMonth(month: MonthOfYear, is_leap_year: bool) u5 {
        return switch (month) {
            // zig fmt: off
            .January   => 31,
            .February  => if (is_leap_year) 29 else 28,
            .March     => 31,
            .April     => 30,
            .May       => 31,
            .June      => 30,
            .July      => 31,
            .August    => 31,
            .September => 30,
            .October   => 31,
            .November  => 30,
            .December  => 31,
            // zig fmt: on
        };
    }

    pub fn fromCalendarDayOfYearChecked(day: DayOfYear, is_leap_year: bool) Error!MonthOfYear {
        if (is_leap_year and day.toOrdinalDay() > 366) return Error.UnrepresentableDay;
        if (!is_leap_year and day.toOrdinalDay() > 365) return Error.UnrepresentableDay;

        return fromCalendarDayOfYear(day, is_leap_year);
    }

    pub fn fromCalendarDayOfYear(day: DayOfYear, is_leap_year: bool) MonthOfYear {
        return if (is_leap_year) switch (day.toRegularDay()) {
            // zig fmt: off
            1 ...  31 => .January,
            32 ...  60 => .February,
            61 ...  91 => .March,
            92 ... 121 => .April,
            122 ... 152 => .May,
            153 ... 182 => .June,
            183 ... 213 => .July,
            214 ... 244 => .August,
            245 ... 274 => .September,
            275 ... 305 => .October,
            306 ... 335 => .November,
            336 ... 366 => .December,
            // zig fmt: on
            else => unreachable,
        } else switch (day.toRegularDay()) {
            // zig fmt: off
              1 ...  31 => .January,
             32 ...  59 => .February,
             60 ...  90 => .March,
             91 ... 120 => .April,
            121 ... 151 => .May,
            152 ... 181 => .June,
            182 ... 212 => .July,
            213 ... 243 => .August,
            244 ... 273 => .September,
            274 ... 304 => .October,
            305 ... 334 => .November,
            335 ... 365 => .December,
            // zig fmt: on
            else => unreachable,
        };
    }

    pub fn ordinalNumberOfFirstOfMonth(month: MonthOfYear, is_leap_year: bool) u9 {
        const non_leap_year: u9 = switch (month) {
            // zig fmt: off
            .January   =>   0,
            .February  =>  31,
            .March     =>  59,
            .April     =>  90,
            .May       => 120,
            .June      => 151,
            .July      => 181,
            .August    => 212,
            .September => 243,
            .October   => 273,
            .November  => 304,
            .December  => 334,
            // zig fmt: on
        };

        return non_leap_year +
            @intFromBool(is_leap_year and month != .January and month != .February);
    }

    test {
        const expectEqual = std.testing.expectEqual;

        var month: MonthOfYear = .January;

        const expected = [12]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        const expected_leap = [12]u8{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

        for (0..24) |i| {
            defer month = month.next();

            try expectEqual(expected[i % 12], month.daysInMonth(false));
            try expectEqual(expected_leap[i % 12], month.daysInMonth(true));
        }
        try expectEqual(MonthOfYear.January, month);

        for (0..24) |i| {
            month = month.prev();

            try expectEqual(expected[11 - i % 12], month.daysInMonth(false));
            try expectEqual(expected_leap[11 - i % 12], month.daysInMonth(true));
        }
        try expectEqual(MonthOfYear.January, month);
    }

    pub fn calendarDayOfMonth(month: MonthOfYear, is_leap_year: bool, day_of_year: DayOfYear) DayOfMonth {
        const ordinal_days_before_month = month.ordinalNumberOfFirstOfMonth(is_leap_year);
        const ordinal_day_of_year = day_of_year.toOrdinalDay();

        assert(ordinal_days_before_month <= ordinal_day_of_year);

        return DayOfMonth.fromOrdinal(ordinal_day_of_year - ordinal_days_before_month, month, is_leap_year);
    }

    pub fn parse(string: []const u8) ?MonthOfYear {
        inline for (std.meta.tags(MonthOfYear)) |tag| {
            if (std.ascii.eqlIgnoreCase(u8, string, @tagName(tag))) return tag;
        }
        return null;
    }

    pub fn parseShort(string: [3]u8) ?MonthOfYear {
        inline for (std.meta.tags(MonthOfYear)) |tag| {
            if (std.ascii.eqlIgnoreCase(u8, string[0..3], @tagName(tag)[0..3])) return tag;
        }
        return null;
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.toOrdinal(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else if (std.mem.eql(u8, fmt, "long")) {
            try writer.writeAll(@tagName(value));
        } else {
            try std.fmt.formatInt(value.toMonthNumber(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

/// Week 0 corresponds to the first week of gregorian year 0
pub const Week = enum(i44) {
    _,

    const min = Week.fromUnchecked(-15250284452471);
    const max = Week.fromUnchecked(15250284452471);

    pub fn from(week: anytype) Week {
        const week_cast: i44 = @intCast(week);

        assert(week_cast >= min.to());
        assert(week_cast <= max.to());

        return fromUnchecked(week);
    }

    fn fromUnchecked(week: i44) Week {
        return @enumFromInt(week);
    }

    pub fn to(week: Week) i44 {
        assert(week.isValid());

        return toUnchecked(week);
    }

    fn toUnchecked(week: Week) i44 {
        return @intFromEnum(week);
    }

    pub fn isValid(week: Week) bool {
        return week.toUnchecked() >= min.toUnchecked() and
            week.toUnchecked() <= max.toUnchecked();
    }
};

pub const WeekOfYear = enum(u6) {
    invalid = 0,
    _,

    pub const Error = error{UnrepresentableWeek};

    pub fn fromOrdinal(week: anytype, year: Year) WeekOfYear {
        const week_cast: u6 = @intCast(week);

        assert(week < year.weeksInYear());

        return fromOrdinalUnchecked(week_cast);
    }

    pub fn fromOrdinalChecked(week: anytype, year: Year) Error!WeekOfYear {
        const week_cast: u6 = cast(u6, week) catch
            return Error.UnrepresentableWeek;

        if (week >= year.weeksInYear())
            return Error.UnrepresentableWeek;

        return fromOrdinalUnchecked(week_cast);
    }

    fn fromOrdinalUnchecked(week: u6) WeekOfYear {
        return @enumFromInt(week + 1);
    }

    pub fn to(week: WeekOfYear, year: Year) u6 {
        assert(week.isValid(year));

        return toUnckecked(week);
    }

    fn toUnckecked(week: WeekOfYear) u6 {
        return @intFromEnum(week) - 1;
    }

    pub fn isValid(week: WeekOfYear, year: Year) bool {
        return week.toUnckecked() >= 1 and
            week.toUnckecked() <= year.weeksInYear();
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.toUnckecked(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            try std.fmt.formatInt((value), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

pub const Day = enum(i48) {
    _,

    const max_day = 106751991167300;
    const min_day = -106751991167300;

    pub const Error = error{UnrepresentableDay};

    pub fn fromOrdinalDay(oridnal_day: i64) Day {
        return @enumFromInt(oridnal_day);
    }

    pub fn fromOrdinalDayChecked(oridnal_day: i64) Error!Day {
        if (oridnal_day > max_day or oridnal_day < min_day)
            return Error.UnrepresentableDay;

        return @enumFromInt(oridnal_day);
    }

    pub fn toOrdinal(day: Day) i48 {
        assert(isValid(day));

        return toOrdinalUnchecked(day);
    }

    pub fn toOrdinalUnchecked(day: Day) i48 {
        return @intFromEnum(day);
    }

    pub fn isValid(day: Day) bool {
        return day.toOrdinalUnchecked() <= max_day and
            day.toOrdinalUnchecked() >= min_day;
    }
};

// One based representation of the day in a given year
pub const DayOfYear = enum(u9) {
    invalid = 0,
    _,

    pub const Error = error{UnrepresentableDay};

    pub fn fromOrdinalSecond(ordinal_second: anytype, is_leap_year: bool) DayOfYear {
        return fromOrdinalDay(@divTrunc(ordinal_second, s_per_day), is_leap_year);
    }

    pub fn fromCalendarDay(calendar_day: Day, is_leap_year: bool) DayOfYear {
        return fromOrdinalDay(calendar_day.toOrdinal(), is_leap_year);
    }

    pub fn fromOrdinalDay(ordinal_day: anytype, is_leap_year: bool) DayOfYear {
        const ordinal_day_cast: u9 = @intCast(ordinal_day);

        const min_ordinal_day: u8 = 0;
        const max_ordinal_day: u9 = 364 + @as(u9, @intFromBool(is_leap_year));

        assert(ordinal_day_cast <= max_ordinal_day);
        assert(ordinal_day_cast >= min_ordinal_day);

        return @enumFromInt(ordinal_day_cast + 1);
    }

    pub fn fromSecondChecked(ordinal_second: anytype, is_leap_year: bool) Error!DayOfYear {
        return fromOrdinalDayChecked(@divTrunc(ordinal_second, s_per_day), is_leap_year);
    }

    pub fn fromOrdinalDayChecked(ordinal_day: anytype, is_leap_year: bool) Error!DayOfYear {
        const ordinal_day_cast: u9 = cast(u9, ordinal_day + 1) orelse
            return Error.UnrepresentableDay;

        const min_ordinal_day: u9 = 1;
        const max_ordinal_day: u9 = 355 + @as(u9, @intCast(@intFromBool(is_leap_year)));

        if (ordinal_day_cast < min_ordinal_day or ordinal_day_cast > max_ordinal_day)
            return Error.UnrepresentableDay;

        return @enumFromInt(ordinal_day_cast);
    }

    pub fn toOrdinalDay(day_of_year: DayOfYear) u9 {
        return @intFromEnum(day_of_year) - 1;
    }

    pub fn toRegularDay(day_of_year: DayOfYear) u9 {
        return @intFromEnum(day_of_year);
    }

    pub fn isValid(self: DayOfYear, is_leap_year: bool) bool {
        const max_ordinal_day = 355 + @intFromBool(is_leap_year);

        return self != .invalid and
            self.toRegularDay() <= max_ordinal_day;
    }
};

pub const DayOfMonth = enum(u5) {
    invalid = 0,
    _,

    pub const Error = error{UnrepresentableDayOfMonth};

    pub fn fromOrdinal(day: anytype, month: MonthOfYear, is_leap_year: bool) DayOfMonth {
        return from(day + 1, month, is_leap_year);
    }

    pub fn toOrdinal(day_of_month: DayOfMonth) u5 {
        return toRegularDay(day_of_month) - 1;
    }

    pub fn toRegularDay(day_of_month: DayOfMonth) u5 {
        return @intFromEnum(day_of_month);
    }

    pub fn from(day: anytype, month: MonthOfYear, is_leap_year: bool) DayOfMonth {
        const cast_day: u5 = @intCast(day);

        assert(cast_day >= 1);
        assert(cast_day <= month.daysInMonth(is_leap_year));

        return @enumFromInt(cast_day);
    }

    pub fn fromChecked(day: anytype, month: MonthOfYear, is_leap_year: bool) Error!DayOfMonth {
        const cast_day: u5 = cast(u5, day) orelse return Error.UnrepresentableDayOfMonth;

        if (cast_day == 0 or cast_day > month.daysInMonth(is_leap_year))
            return Error.UnrepresentableDayOfMonth;

        return @enumFromInt(cast_day);
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.toOrdinal(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            try std.fmt.formatInt(value.toRegularDay(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

pub const DayOfWeek = enum(u3) {
    // zig fmt: off
    Monday    = 1,
    Tuesday   = 2,
    Wednesday = 3,
    Thursday  = 4,
    Friday    = 5,
    Saturday  = 6,
    Sunday    = 7,
    // zig fmt: on

    pub fn fromOrdinal(day: u3) DayOfWeek {
        return @enumFromInt(day + 1);
    }

    pub fn toOrdinal(day: DayOfWeek) u3 {
        return @intFromEnum(day) - 1;
    }

    pub fn next(day: DayOfWeek) DayOfWeek {
        return switch (day) {
            // zig fmt: off
            .Monday    => .Tuesday,
            .Tuesday   => .Wednesday,
            .Wednesday => .Thursday,
            .Thursday  => .Friday,
            .Friday    => .Saturday,
            .Saturday  => .Sunday,
            .Sunday    => .Monday,
            // zig fmt: on
        };
    }

    pub fn prev(day: DayOfWeek) DayOfWeek {
        return switch (day) {
            // zig fmt: off
            .Monday    => .Sunday,
            .Tuesday   => .Monday,
            .Wednesday => .Tuesday,
            .Thursday  => .Wednesday,
            .Friday    => .Thursday,
            .Saturday  => .Friday,
            .Sunday    => .Saturday,
            // zig fmt: on
        };
    }

    pub fn parse(string: []const u8) ?DayOfWeek {
        inline for (std.meta.tags(DayOfWeek)) |tag| {
            if (std.ascii.eqlIgnoreCase(u8, string, @tagName(tag))) return tag;
        }
        return null;
    }

    pub fn parseShort(string: [3]u8) ?DayOfWeek {
        inline for (std.meta.tags(DayOfWeek)) |tag| {
            if (std.ascii.eqlIgnoreCase(u8, string[0..3], @tagName(tag)[0..3])) return tag;
        }
        return null;
    }
};

pub const Hour = enum(u5) {
    _,

    pub const Error = error{UnrepresentableHour};

    pub fn from(hour: anytype) Hour {
        const hour_cast: u5 = @intCast(hour);

        assert(hour_cast <= 24);

        return fromUnchecked(hour_cast);
    }

    pub fn fromChecked(hour: anytype) Error!Hour {
        const hour_cast: u5 = @intCast(hour);

        if (hour_cast > 24)
            return Error.UnrepresentableHour;

        return fromUnchecked(hour_cast);
    }

    fn fromUnchecked(hour: u5) Hour {
        return @enumFromInt(hour);
    }

    pub fn toOridnal(hour: Hour) u5 {
        return @intFromEnum(hour);
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.toOridnal(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            try std.fmt.formatInt(value.toOridnal(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

pub const Minute = enum(u6) {
    _,

    pub fn fromOrdinal(minute: anytype) Minute {
        return @enumFromInt(minute);
    }

    pub fn toOrdinal(minute: Minute) u6 {
        return @intFromEnum(minute);
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.toOrdinal(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            try std.fmt.formatInt(value.toOrdinal(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

pub const Second = enum(u6) {
    _,

    pub fn fromOrdinal(minute: anytype) Second {
        return @enumFromInt(minute);
    }

    pub fn toOrdinal(second: Second) u6 {
        return @intFromEnum(second);
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.toOrdinal(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            try std.fmt.formatInt(value.toOrdinal(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

pub fn getCalendarDay(self: DateTime) Day {
    return Day.fromOrdinalDay(@divTrunc(self.timestamp, s_per_day));
}

test getCalendarDay {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(Day.fromOrdinalDay(719_528), unixEpoch.getCalendarDay());
}

pub fn getYear(self: DateTime) Year {
    return Year.fromCalendarDay(self.getCalendarDay());
}

test getYear {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(Year.from(0), gregorianEpoch.getYear());
    try expectEqual(Year.from(1970), unixEpoch.getYear());

    const @"2024-01-01T00:00:00Z" = DateTime{ .timestamp = 63871286400 };
    const @"2024-12-31T23:59:59Z" = DateTime{ .timestamp = 63902908799 };
    const @"2025-01-01T00:00:00Z" = DateTime{ .timestamp = 63902908800 };
    const @"2025-12-31T23:59:59Z" = DateTime{ .timestamp = 63934444799 };

    try expectEqual(Year.from(2024), @"2024-01-01T00:00:00Z".getYear());
    try expectEqual(Year.from(2024), @"2024-12-31T23:59:59Z".getYear());
    try expectEqual(Year.from(2025), @"2025-01-01T00:00:00Z".getYear());
    try expectEqual(Year.from(2025), @"2025-12-31T23:59:59Z".getYear());
}

pub fn getDayOfYear(self: DateTime) DayOfYear {
    const year = self.getYear();

    // To deal with the case of timestamp == minInt(i64), in this case the start
    // of the year is ~ 25 days before what our timestamp can represent and
    // would thus overflow :'(
    const days_to_ignore: i65 = year.daysSinceGregorianEpoch() +
        (365 * @as(i65, @intFromBool(year.to() < 0)));
    // FIXME: explain why???
    // I have the feeling this is related to the fact `daysSinceGregorianEpoch`
    // counts from the start of the year, for negatives. Might be a reason to
    // change this behavior

    const seconds_to_ignore = days_to_ignore * s_per_day;

    const seconds_in_year = @as(u65, @abs(self.timestamp)) - @as(u65, @abs(seconds_to_ignore));

    assert(seconds_in_year <= @as(u64, year.getDaysInYear()) * s_per_day);
    assert(seconds_in_year >= 0);

    return DayOfYear.fromOrdinalSecond(seconds_in_year, year.isLeapYear());
}

test getDayOfYear {
    const @"2024-01-01T00:00:00Z" = DateTime{ .timestamp = 63871286400 };
    const @"2024-12-31T23:59:59Z" = DateTime{ .timestamp = 63902908799 };
    const @"2025-01-01T00:00:00Z" = DateTime{ .timestamp = 63902908800 };
    const @"2025-12-31T23:59:59Z" = DateTime{ .timestamp = 63934444799 };

    // const min = DateTime{ .timestamp = minInt(i64) };
    // const max = DateTime{ .timestamp = maxInt(i64) };

    const fromOrdinalDay = DayOfYear.fromOrdinalDay;

    try std.testing.expectEqual(fromOrdinalDay(0, true), @"2024-01-01T00:00:00Z".getDayOfYear());
    try std.testing.expectEqual(fromOrdinalDay(365, true), @"2024-12-31T23:59:59Z".getDayOfYear());
    try std.testing.expectEqual(fromOrdinalDay(0, false), @"2025-01-01T00:00:00Z".getDayOfYear());
    try std.testing.expectEqual(fromOrdinalDay(364, false), @"2025-12-31T23:59:59Z".getDayOfYear());

    // try std.testing.expectEqual(fromOrdinalDay(25, false), min.getDayOfYear());
    // try std.testing.expectEqual(fromOrdinalDay(338, false), max.getDayOfYear());
}

pub fn getMonth(self: DateTime) MonthOfYear {
    return MonthOfYear.fromCalendarDayOfYear(
        self.getDayOfYear(),
        self.getYear().isLeapYear(),
    );
}

test getMonth {

    // Leap year bounds
    const @"2024-01-01T00:00:00Z" = DateTime{ .timestamp = 63871286400 };
    const @"2024-12-31T23:59:59Z" = DateTime{ .timestamp = 63902908799 };

    // Month bounds
    // TODO: make these when I can get a datetime from human readable dates

    // Non leap year bounds
    const @"2025-01-01T00:00:00Z" = DateTime{ .timestamp = 63902908800 };
    const @"2025-12-31T23:59:59Z" = DateTime{ .timestamp = 63934444799 };

    try std.testing.expectEqual(MonthOfYear.January, @"2024-01-01T00:00:00Z".getMonth());
    try std.testing.expectEqual(MonthOfYear.December, @"2024-12-31T23:59:59Z".getMonth());
    try std.testing.expectEqual(MonthOfYear.January, @"2025-01-01T00:00:00Z".getMonth());
    try std.testing.expectEqual(MonthOfYear.December, @"2025-12-31T23:59:59Z".getMonth());
}

pub fn getDayOfMonth(self: DateTime) DayOfMonth {
    const year = self.getYear();
    const month = self.getMonth();
    const day_of_year = self.getDayOfYear();
    return month.calendarDayOfMonth(year.isLeapYear(), day_of_year);
}

pub fn getHour(date: DateTime) Hour {
    return Hour.from(@divTrunc(@mod(date.timestamp, s_per_day), s_per_hour));
}

pub fn getMinute(date: DateTime) Minute {
    return Minute.fromOrdinal(@divTrunc(@mod(date.timestamp, s_per_hour), s_per_min));
}

pub fn getSecond(date: DateTime) Second {
    return Second.fromOrdinal(@mod(date.timestamp, s_per_min));
}

// FIXME: better name pls
pub const BuildOptions = struct {
    year: i40,
    month: MonthOfYear = .January,
    day_of_month: u5 = 1,
};

pub fn build(b: BuildOptions) DateTime {
    const year = Year.from(b.year);
    const day_of_month_cast = DayOfMonth.from(b.day_of_month, b.month, year.isLeapYear());

    return DateTime.gregorianEpoch
        .setYear(year)
        .addDays(b.month.ordinalNumberOfFirstOfMonth(year.isLeapYear()))
        .addDays(day_of_month_cast.toOrdinal());
}

pub const BuildOptionsTyped = struct {
    year: Year,
    month: MonthOfYear,
    day_of_month: DayOfMonth,
};

pub fn buildTyped(b: BuildOptionsTyped) DateTime {
    return DateTime.gregorianEpoch
        .setYear(b.year)
        .addDays(b.month.ordinalNumberOfFirstOfMonth(b.year.isLeapYear()))
        .addDays(b.day_of_month.toOrdinal());
}

pub fn buildChecked(b: BuildOptions) !DateTime {
    const year = try Year.fromChecked(b.year);
    const day_of_month_cast = try DayOfMonth.fromChecked(b.day_of_month, b.month, year.isLeapYear());

    return DateTime.gregorianEpoch
        .setYear(year)
        .addDays(b.month.ordinalNumberOfFirstOfMonth(year.isLeapYear()))
        .addDays(day_of_month_cast.toOrdinal());
}

test build {
    const expectEqual = std.testing.expectEqual;
    _ = expectEqual;

    // try expectEqual(unixEpoch, try build(.{ .year = 1970, .month = .January, .day_of_month = 1 }));
}

pub fn fromUnixTimestamp(timestamp: i64) DateTime {
    return unixEpoch.addSeconds(timestamp);
}

pub fn fromGregorianTimestamp(timestamp: i64) DateTime {
    return gregorianEpoch.addSeconds(timestamp);
}

pub fn now() DateTime {
    return fromUnixTimestamp(std.time.timestamp());
}

pub fn setYear(date: DateTime, year: Year) DateTime {
    assert(year.isValid());

    const ordinal_day_of_year = date.getDayOfYear().toOrdinalDay();
    const days_to_year = year.daysSinceGregorianEpoch();

    return gregorianEpoch.addDays(days_to_year + ordinal_day_of_year);
}

test setYear {
    const expectEqual = std.testing.expectEqual;

    const zero = DateTime.gregorianEpoch;
    const hunderd = DateTime.gregorianEpoch.setYear(Year.from(100));
    const thousand = DateTime.gregorianEpoch.setYear(Year.from(1000));

    try expectEqual(Year.from(123), zero.setYear(Year.from(123)).getYear());
    try expectEqual(Year.from(123), hunderd.setYear(Year.from(123)).getYear());
    try expectEqual(Year.from(123), thousand.setYear(Year.from(123)).getYear());
}

pub fn addSeconds(date: DateTime, seconds: i64) DateTime {
    return .{
        .timestamp = date.timestamp + seconds,
    };
}

pub fn addMinutes(date: DateTime, minutes: i64) DateTime {
    return .{
        .timestamp = date.timestamp + minutes * s_per_min,
    };
}

pub fn addHours(date: DateTime, hours: i64) DateTime {
    return .{
        .timestamp = date.timestamp + hours * s_per_hour,
    };
}

pub fn addDays(date: DateTime, ordinal_days: i64) DateTime {
    return .{
        .timestamp = date.timestamp + ordinal_days * s_per_day,
    };
}

pub fn addWeeks(date: DateTime, weeks: i64) DateTime {
    return .{
        .timestamp = date.timestamp + weeks * s_per_week,
    };
}

// TODO: Extensively test over leap years
pub fn addMonths(date: DateTime, months: i64) DateTime {
    const day_of_month = date.getDayOfMonth();

    const years_to_add = Year.from(@divTrunc(months, 12));
    const months_to_add = @rem(months, 12);
    const month_ordial = date.getMonth().toOrdinal();

    const new_month_ordinal: u4 = @intCast(@mod(month_ordial + months_to_add, 12));
    const years_overflowed = Year.from(@divFloor(month_ordial + months_to_add, 12));

    const new_month = MonthOfYear.fromOrdinal(new_month_ordinal);
    const new_year = Year.from(date.getYear().to() +
        years_to_add.to() +
        years_overflowed.to());

    return DateTime.gregorianEpoch
        .setYear(new_year)
        .addDays(new_month.ordinalNumberOfFirstOfMonth(new_year.isLeapYear()))
        .addDays(day_of_month.toOrdinal());
}

test addMonths {
    const expectEqual = std.testing.expectEqual;

    const steps = [_]struct { u8, u8 }{
        .{ 12, 1 },
        .{ 6, 2 },
        .{ 3, 4 },
        .{ 1, 12 },
    };

    for (steps) |step| {
        var date_pos = gregorianEpoch;
        // var date_neg = gregorianEpoch;

        for (1..500) |year| {
            for (0..step.@"1") |_| {
                date_pos = date_pos.addMonths(step.@"0");
                // date_neg = date_neg.addMonths(-@as(i9, step.@"0"));
            }

            try expectEqual(DayOfYear.fromOrdinalDay(0, false), date_pos.getDayOfYear());
            try expectEqual(.January, date_pos.getMonth());
            try expectEqual(Year.from(year), date_pos.getYear());

            // FIXME: Make these tests work
            // try expectEqual(DayOfYear.fromOrdinalDay(0, false), date_neg.getDayOfYear());
            // try expectEqual(.January, date_neg.getMonth());
            // try expectEqual(Year.from(-@as(isize, @intCast(year))), date_neg.getYear());
        }
    }
}

pub fn addYears(date: DateTime, years: i64) DateTime {
    const day_of_year = date.getDayOfYear();
    const year = Year.from(date.getYear().to() + years);

    return gregorianEpoch
        .setYear(year)
        .addDays(day_of_year.toOrdinalDay());
}

test addYears {
    const expectEqual = std.testing.expectEqual;

    for (1..100) |year_step| {
        var date = gregorianEpoch;

        for (0..1000) |i| {
            const expected_year = year_step * i;

            try expectEqual(DayOfYear.fromOrdinalDay(0, false), date.getDayOfYear());
            try expectEqual(MonthOfYear.January, date.getMonth());
            try expectEqual(Year.from(expected_year), date.getYear());

            date = date.addYears(@intCast(year_step));
        }
    }
}

pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = options;
    _ = fmt;

    try std.fmt.format(
        writer,
        "{}-{}-{}T{}:{}:{}Z",
        .{
            value.getYear(),
            value.getMonth(),
            value.getDayOfMonth(),
            value.getHour(),
            value.getMinute(),
            value.getSecond(),
        },
    );
}

const DateTime = @This();

const std = @import("std");
const time = std.time;
const s_per_week = time.s_per_week;
const s_per_day = time.s_per_day;
const s_per_hour = time.s_per_hour;
const s_per_min = time.s_per_min;
const assert = std.debug.assert;
const minInt = std.math.minInt;
const maxInt = std.math.maxInt;
const cast = std.math.cast;

fn functions(comptime Type: type) void {
    const decls: []const std.builtin.Type.Declaration = switch (@typeInfo(Type)) {
        .@"struct" => |info| info.decls,
        .@"enum" => |info| info.decls,
        else => @compileError("no"),
    };

    std.debug.print("Type: {s}\n", .{@typeName(Type)});
    inline for (decls) |decl| {
        if (@typeInfo(@TypeOf(@field(Type, decl.name))) == .@"fn") {
            std.debug.print("\t{s}\n", .{decl.name});
        }
    }
    std.debug.print("\n", .{});
}

test {
    // functions(Year);
    //
    // functions(MonthOfYear);
    //
    // functions(Week);
    // functions(WeekOfYear);
    //
    // functions(Day);
    // functions(DayOfYear);
    // functions(DayOfMonth);
    // functions(DayOfWeek);
    //
    // functions(Hour);
    // functions(Minute);
    // functions(Second);

    _ = Year;

    // No month, as there is no month calendar (it'd also be truly painful)
    _ = MonthOfYear;

    _ = Week;
    _ = WeekOfYear;

    _ = Day;

    _ = DayOfYear;
    _ = DayOfMonth;
    _ = DayOfWeek;

    _ = Hour;
    _ = Minute;
    _ = Second;
}
