//! A date and time representation based on ISO 8600-1:2019 representing only UTC.
//! Other timezones are represented through {TIMEZONE_WRAPPER}
//! TODO: Add timezone wrapper; see todo.md
//!
//! This implementation can represent dates from
//!     -292277024626-01-01T00:00:00Z to (-292 billion)
//!      292277024625-12-31T23:59:59Z    ( 292 billion)
//! This is notably less than what an i64 can represent, but this way
//! every supported year is fully supported from january 1st to december 31st
//! instead of cutting off at an arbirtrary date.
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

pub const gregorianEpoch: DateTime = .{ .timestamp = 0 };
pub const unixEpoch: DateTime = .{ .timestamp = 62_167_219_200 };

pub const date_min: DateTime = .{ .timestamp = -9223372036825430400 };
pub const date_max: DateTime = .{ .timestamp = 9223372036825516799 };

test "epoch" {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    try expectEqual(build(.{ .year = 0, .month = .January, .day_of_month = 1 }), gregorianEpoch);
    try expectEqual(build(.{ .year = 1970, .month = .January, .day_of_month = 1 }), unixEpoch);
}

/// Type safe representation of a year, centered around the year 0
/// of the gregorian calendar
///
/// To obtain a `Year` it's reccomended to use `Year.from` as that does some
/// aditional bounds checks
pub const Year = enum(i40) {
    _,

    pub const min = Year.fromUnchecked(-292277024626);
    pub const max = Year.fromUnchecked(292277024625);

    test "min/max" {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(build(.{ .year = min.to() }).getYear(), min);
        try expectEqual(build(.{ .year = max.to() }).getYear(), max);
    }

    pub const Error = error{UnrepresentableYear};

    /// Convert any integer type to a type safe year.
    ///
    /// This function assumes that the year you provide is valid, and representable
    /// by the `DateTime` timestamp
    pub fn from(year: i40) Year {
        assert(year >= min.to());
        assert(year <= max.to());

        return fromUnchecked(year);
    }

    /// Convert any integer type to a type safe year.
    ///
    /// If the year cannot be represented by the `DateTime` timestamp, this
    /// function returns `UnrepresetableYear`. This only happes for years more
    /// than ~292 billion years removed from year 0.
    pub fn fromChecked(year: i40) Error!Year {
        if (year < min.to()) return Error.UnrepresentableYear;
        if (year > max.to()) return Error.UnrepresentableYear;

        return fromUnchecked(year);
    }

    fn fromUnchecked(year: i40) Year {
        return @enumFromInt(year);
    }

    test from {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(123, Year.from(123).to());
        try expectEqual(-123, Year.from(-123).to());
        try expectEqual(1000, Year.from(1000).to());
        try expectEqual(0, Year.from(0).to());

        try expectEqual(min, Year.from(min.to()));
        try expectEqual(max, Year.from(max.to()));
    }

    test fromChecked {
        @disableInstrumentation();

        const expectError = std.testing.expectError;
        const expectEqual = std.testing.expectEqual;

        try expectEqual(123, Year.from(123).to());
        try expectEqual(-123, Year.from(-123).to());
        try expectEqual(1000, Year.from(1000).to());
        try expectEqual(0, Year.from(0).to());

        try expectEqual(min, Year.from(min.to()));
        try expectEqual(max, Year.from(max.to()));

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
            return Error.UnrepresentableYear;

        return toUnchecked(year);
    }

    fn toUnchecked(year: Year) i40 {
        return @intFromEnum(year);
    }

    pub fn isValid(year: Year) bool {
        return year.toUnchecked() >= min.toUnchecked() and
            year.toUnchecked() <= max.toUnchecked();
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
        @disableInstrumentation();

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
            const year_pos = Year.from(@intCast(i));
            const year_neg = Year.from(@intCast(i));

            try expectEqual(year_pos.isLeapYear(), year_neg.isLeapYear());
        }
    }

    /// The amount of leap years before and including the current year and year
    /// 0.
    pub fn leapYearsSinceGregorianEpoch(year: Year) i40 {
        // zig fmt: off
        // Leap years can be thought of as 4 different cycles, 
        // 1) a 400 year cycle which starts and ends in a centennial year divisible by 400, 
        // 2) a 100 year cycle which starts and ends in a centennial year not divisible by 400
        // 3) a   4 year cycle which starts and ends in a regular leap year
        // 4) a   1 year cycle which starts and ends in a regular year
        const leap_400 = 97; // The 400 year cycle has 97 leap years
        const leap_100 = 24; // The 100 year cycle has 24 leap years
        const leap_4   =  1; // The   4 year cycle has  1 leap year
        // zig fmt: on

        var year_int: i40 = year.to();

        // We want to use divTrunc because year_int -1 is 0 cycles
        const cycle_400 = @divTrunc(year_int, 400);
        year_int = @rem(year_int, 400);

        // We want to use divTrunc because year_int -1 is 0 cycles
        const cycle_100 = @divTrunc(year_int, 100);
        year_int = @rem(year_int, 100);

        // We want to use divTrunc because year_int -1 is 0 cycles
        const cycle_4 = @divTrunc(year_int, 4);

        return cycle_400 * leap_400 +
            cycle_100 * leap_100 +
            cycle_4 * leap_4 +
            // One more to account for the fact year 0 is a leap year
            @intFromBool(year.to() >= 0);
    }

    test leapYearsSinceGregorianEpoch {
        @disableInstrumentation();

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
            const year_pos: Year = Year.from(@intCast(i));
            const year_neg: Year = Year.from(@intCast(i));

            try expectEqual(year_pos.isLeapYear(), year_neg.isLeapYear());

            if (year_neg.isLeapYear()) found_leap_years += 1;

            try expectEqual(found_leap_years, leapYearsSinceGregorianEpoch(year_pos));
            try expectEqual(found_leap_years, leapYearsSinceGregorianEpoch(year_neg));
        }
    }

    /// The amount of days between January 1st of year 0, and January 1st of `year`
    ///
    /// For year 1, this would be 366 days, as year 0 is a leap year.
    /// However for year -1, this is -365, and for year -4 this is
    /// -1_461 (notably, the leap day is counted)
    pub fn daysSinceGregorianEpoch(year: Year) i64 {
        const year_int: i64 = year.to();

        return year_int * 365 + leapYearsSinceGregorianEpoch(year) -
            @intFromBool(isLeapYear(year) and year.to() >= 0);
    }

    test daysSinceGregorianEpoch {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(0, daysSinceGregorianEpoch(Year.from(0)));
        try expectEqual(366, daysSinceGregorianEpoch(Year.from(1)));
        try expectEqual(-365, daysSinceGregorianEpoch(Year.from(-1)));

        const tst = struct {
            pub fn tst(day: i64, year: i40) !void {
                @disableInstrumentation();
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

        const tstraw = struct {
            pub fn tstraw(day: i64, year: i40) !void {
                @disableInstrumentation();
                try expectEqual(day, Year.from(year).daysSinceGregorianEpoch());
            }
        }.tstraw;

        // Near zero
        try tstraw(366 * 1 + 365 * 0, 1);
        try tstraw(366 * 1 + 365 * 1, 2);
        try tstraw(366 * 1 + 365 * 2, 3);
        try tstraw(366 * 1 + 365 * 3, 4);
        try tstraw(366 * 2 + 365 * 3, 5);

        try tstraw(-366 * 0 - 365 * 1, -1);
        try tstraw(-366 * 0 - 365 * 2, -2);
        try tstraw(-366 * 0 - 365 * 3, -3);
        try tstraw(-366 * 1 - 365 * 3, -4);
        try tstraw(-366 * 1 - 365 * 4, -5);

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

        var days_left = day.to();

        // Correct for the fact that year 0 is a leap year
        days_left -= @intFromBool(days_left > 0);

        // TODO: See if I can remove this by using divfloor over divtrunc

        // Since day -365 corresponds to the start of year -1, we subtract 364
        // to properly align ourselves (-1 - 364 == -365)
        days_left -= 364 * @as(i48, @intFromBool(days_left < 0));

        const cycle_400: i40 = @intCast(@divTrunc(days_left, d_in_cycle_400));
        days_left = @rem(days_left, d_in_cycle_400);

        const cycle_100: i40 = @intCast(@divTrunc(days_left, d_in_cycle_100));
        days_left = @rem(days_left, d_in_cycle_100);

        const cycle_4: i40 = @intCast(@divTrunc(days_left, d_in_cycle_4));
        days_left = @rem(days_left, d_in_cycle_4);

        const cycle_1: i40 = @intCast(@divTrunc(days_left, d_in_cycle_1));

        return Year.from(cycle_400 * 400 +
            cycle_100 * 100 +
            cycle_4 * 4 +
            cycle_1);
    }

    test fromCalendarDay {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        // This is really hard to get right, do some hard coded manually verified tests

        // Year 0 starts on day 0
        try expectEqual(Year.from(0), fromCalendarDay(Day.from(0)));
        // Year 0 is 366 days long, since day 0 is a day, 365 is the last day
        try expectEqual(Year.from(0), fromCalendarDay(Day.from(365)));

        // Year 0 end + 1
        try expectEqual(Year.from(1), fromCalendarDay(Day.from(366)));
        // Year 1 start + 364, again because day 366 is part of year 1
        try expectEqual(Year.from(1), fromCalendarDay(Day.from(730)));

        // Year 1 end + 1
        try expectEqual(Year.from(2), fromCalendarDay(Day.from(731)));
        // Year 2 start + 364
        try expectEqual(Year.from(2), fromCalendarDay(Day.from(1095)));

        // Year 2 end + 1
        try expectEqual(Year.from(3), fromCalendarDay(Day.from(1096)));
        // Year 3 start + 364
        try expectEqual(Year.from(3), fromCalendarDay(Day.from(1460)));

        // Year 3 end + 1
        try expectEqual(Year.from(4), fromCalendarDay(Day.from(1461)));
        // Year 4 start + 365, since year 4 is a leap year
        try expectEqual(Year.from(4), fromCalendarDay(Day.from(1826)));

        // Year 4 end + 1
        try expectEqual(Year.from(5), fromCalendarDay(Day.from(1827)));
        // Year 5 start + 364
        try expectEqual(Year.from(5), fromCalendarDay(Day.from(2191)));

        // Year 0 starts on day 0, so year -1 end at day -1
        try expectEqual(Year.from(-1), fromCalendarDay(Day.from(-1)));
        // Year -1 is not a leap year, thus has 365 days. Year 0 starts on day 0
        // thus the first day of year -1 must be day -365
        try expectEqual(Year.from(-1), fromCalendarDay(Day.from(-365)));

        // Year -1 start - 1
        try expectEqual(Year.from(-2), fromCalendarDay(Day.from(-366)));
        // Year -2 end - 364
        try expectEqual(Year.from(-2), fromCalendarDay(Day.from(-730)));

        // Year -2 start - 1
        try expectEqual(Year.from(-3), fromCalendarDay(Day.from(-731)));
        // Year -3 end - 364
        try expectEqual(Year.from(-3), fromCalendarDay(Day.from(-1_095)));

        // Year -3 start - 1
        try expectEqual(Year.from(-4), fromCalendarDay(Day.from(-1_096)));
        // Year -4 end - 365
        try expectEqual(Year.from(-4), fromCalendarDay(Day.from(-1_461)));

        const tst = struct {
            pub fn tst(ordinal_day: i48, year: i40) !void {
                @disableInstrumentation();
                const year_pos = Year.from(year);
                const year_pos_start = Day.from(ordinal_day);
                const year_pos_end = Day.from(ordinal_day + year_pos.getDaysInYear() - 1);

                try expectEqual(year_pos, fromCalendarDay(year_pos_start));
                try expectEqual(year_pos, fromCalendarDay(year_pos_end));

                const year_neg = Year.from(-year);
                // This is +1 to offset the fact that year 0 is a leap year
                const year_neg_start = Day.from(-ordinal_day + 1);
                // This is -1 as day -1 corresponds to the end of year -1, not day 0
                const year_neg_end = Day.from(-ordinal_day + year_neg.getDaysInYear() - 1);

                try expectEqual(year_neg, fromCalendarDay(year_neg_start));
                try expectEqual(year_neg, fromCalendarDay(year_neg_end));
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

    pub fn firstDay(year: Year) DayOfWeek {
        // Year 0 starts on a Saturday, after that every non leap year
        // starts one day later (Monday -> Tuesday) and every leap year
        // starts two days later (Monday -> Wednesday)
        // Verified through `date`

        const days_moved: i40 = year.to() +
            year.leapYearsSinceGregorianEpoch() -
            // Correct for the fact year 0 is a leap year
            @intFromBool(year.isLeapYear() and year.to() >= 0) +
            DayOfWeek.Saturday.toOrdinal(); // Start on saturday :(

        const week_days_moved: u3 = @intCast(@mod(days_moved, 7));
        return DayOfWeek.from0(week_days_moved);
    }

    test firstDay {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(.Saturday, Year.from(0).firstDay());
        try expectEqual(.Monday, Year.from(1).firstDay());
        try expectEqual(.Tuesday, Year.from(2).firstDay());
        try expectEqual(.Wednesday, Year.from(3).firstDay());
        try expectEqual(.Thursday, Year.from(4).firstDay());
        try expectEqual(.Saturday, Year.from(5).firstDay());
        try expectEqual(.Sunday, Year.from(6).firstDay());
        try expectEqual(.Monday, Year.from(7).firstDay());

        try expectEqual(.Thursday, Year.from(1970).firstDay());
        try expectEqual(.Saturday, Year.from(2000).firstDay());
        try expectEqual(.Monday, Year.from(2024).firstDay());

        try expectEqual(.Friday, Year.from(-1).firstDay());

        // From fuzzer
        try expectEqual(.Friday, Year.from(-35).firstDay());
        try expectEqual(.Wednesday, Year.from(-36).firstDay());
    }

    pub fn weeksInYear(year: Year) u6 {
        // https://en.wikipedia.org/wiki/Week#Week_52_and_53
        // It is also possible to determine if the last week of
        // the previous year was Week 52 or Week 53 as follows:
        // - If 1 January falls on a Friday, then it is part of
        //   Week 53 of the previous year (W53-5).
        // - If 1 January falls on a Saturday,
        //   - then it is part of Week 53 of the previous year if
        //     that is a leap year (W53-6),
        //   - and part of Week 52 otherwise (W52-6), i.e. if
        //     the previous year is a common year.
        // - If 1 January falls on a Sunday, then it is part of
        //   Week 52 of the previous year (W52-7).
        //
        //  However in most cases you want the weeks in the current year
        //
        // Imporant facts:
        // - We know that on a leap year, the day shifts 2 days
        //   foreward (monday -> wednesday),
        // - Otherwise it shifts 1 day foreward (monday -> tuesday)
        return switch (year.firstDay()) {
            // On a leap year Wed -> Fri
            .Wednesday => 52 + @as(u6, @intFromBool(year.isLeapYear())),
            // On a leap year Thu -> Sat
            // On a norm year Thu -> Fri
            .Thursday => 53,
            // Any other combination does not land on Friday
            else => 52,
        };
    }

    test weeksInYear {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(52, Year.from(0).weeksInYear()); // Sat
        try expectEqual(52, Year.from(1).weeksInYear()); // Mon
        try expectEqual(52, Year.from(2).weeksInYear()); // Tue
        try expectEqual(52, Year.from(3).weeksInYear()); // Wed
        try expectEqual(53, Year.from(4).weeksInYear()); // Thu
        try expectEqual(52, Year.from(5).weeksInYear()); // Sat
        try expectEqual(52, Year.from(6).weeksInYear()); // Sun
        try expectEqual(52, Year.from(7).weeksInYear()); // Mon
        try expectEqual(52, Year.from(8).weeksInYear()); // Tue
        try expectEqual(53, Year.from(9).weeksInYear()); // Thu
        try expectEqual(52, Year.from(10).weeksInYear()); // Fri

        // From https://www.epochconverter.com/years
        try expectEqual(52, Year.from(1800).weeksInYear());
        try expectEqual(53, Year.from(1801).weeksInYear());
        try expectEqual(52, Year.from(1802).weeksInYear());

        try expectEqual(52, Year.from(2019).weeksInYear());
        try expectEqual(53, Year.from(2020).weeksInYear());
        try expectEqual(52, Year.from(2021).weeksInYear());
    }

    pub fn firstWeek(year: Year) Week {
        // Facts:
        // - Year 0 starts on week 1, and thus Year(0).weeksSinceEpoch == 1
        //
        // Requirements:
        // - This function must be implemented in constant time
        //   - No recursion
        //   - No runtime loops

        const first_day_of_year = year.firstDay();

        const day_till_monday = if (first_day_of_year.isAfter(.Thursday))
            // We need to find the _next_ monday
            7 - @as(i48, first_day_of_year.toOrdinal())
        else
            // We need to find the _previous_ monday
            -@as(i48, first_day_of_year.toOrdinal());

        const relevant_day: i48 = @intCast(year.daysSinceGregorianEpoch() + day_till_monday);

        return Week.fromDay(Day.from(relevant_day));
    }

    test firstWeek {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        // - Year 0 starts on week 1
        try expectEqual(Week.from(1), Year.from(0).firstWeek());

        const tst = struct {
            pub fn tst(w: i40, y: i40) !void {
                @disableInstrumentation();
                const week = Week.from(w);
                const year = Year.from(y);

                try expectEqual(week, year.firstWeek());
            }
        }.tst;

        try tst(1, 0);
        try tst(53, 1);
        try tst(105, 2);
        try tst(157, 3);
        try tst(209, 4);
        try tst(262, 5);

        try tst(-51, -1);
        try tst(-104, -2);
        try tst(-156, -3);
    }

    pub fn tryNext(year: Year) Error!Year {
        const next_year = Year.fromUnchecked(year.toUnchecked() +| 1);

        if (!next_year.isValid()) return Error.UnrepresentableYear;

        return next_year;
    }

    pub fn tryPrev(year: Year) Error!Year {
        const prev_year = Year.fromUnchecked(year.toUnchecked() -| 1);

        if (!prev_year.isValid()) return Error.UnrepresentableYear;

        return prev_year;
    }

    pub fn format(year: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(year.toUnchecked(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            // Effectively a copy of std.fmt.formatInt, but I wanted a little
            // bit of custom logic with the sign so we ball

            const int_value = year.toChecked() catch {
                try writer.writeAll("Invalid Year (");
                try std.fmt.formatInt(year.toUnchecked(), 10, .lower, .{}, writer);
                try writer.writeAll(")");
                return;
            };

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

    pub fn from(month: u4) MonthOfYear {
        assert(month >= 1);
        assert(month <= 12);

        return fromUnchecked(month);
    }

    pub fn fromChecked(month: u4) Error!MonthOfYear {
        if (month < 0 or month > 11)
            return Error.UnrepresentableMonth;

        return fromUnchecked(month);
    }

    fn fromUnchecked(month: u4) MonthOfYear {
        return @enumFromInt(month);
    }

    pub fn to(month: MonthOfYear) u4 {
        return @intFromEnum(month);
    }

    pub fn from0(month: u4) MonthOfYear {
        return from(month + 1);
    }

    pub fn from0Checked(month: u4) MonthOfYear {
        return fromChecked(month + 1);
    }

    pub fn to0(month: MonthOfYear) u4 {
        return to(month) - 1;
    }

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
        if (day.to0() > 365 + @intFromBool(is_leap_year))
            return Error.UnrepresentableDay;

        return fromCalendarDayOfYear(day, is_leap_year);
    }

    pub fn fromCalendarDayOfYear(day: DayOfYear, is_leap_year: bool) MonthOfYear {
        return if (is_leap_year) switch (day.to()) {
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
        } else switch (day.to()) {
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
        @disableInstrumentation();

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
        const ordinal_day_of_year = day_of_year.to0();

        assert(ordinal_days_before_month <= ordinal_day_of_year);

        return DayOfMonth.fromOrdinal(@intCast(ordinal_day_of_year - ordinal_days_before_month), month, is_leap_year);
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.to0(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else if (std.mem.eql(u8, fmt, "long")) {
            try writer.writeAll(@tagName(value));
        } else {
            try std.fmt.formatInt(value.to(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

/// Week 0 corresponds to the first week of gregorian year 0
pub const Week = enum(i45) {
    _,

    pub const min = Week.fromUnchecked(-15250284452423);
    pub const max = Week.fromUnchecked(15250284452423);

    test "min/max" {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(date_min.getWeek(), min);
        try expectEqual(date_max.getWeek(), max);
    }

    pub fn from(week: i45) Week {
        assert(week >= min.to());
        assert(week <= max.to());

        return fromUnchecked(week);
    }

    fn fromUnchecked(week: i45) Week {
        return @enumFromInt(week);
    }

    pub fn fromDay(day: Day) Week {
        const day_num = day.to();

        // Week 0 starts on the first monday before day 0 (a saturday).
        const day_shifted = day_num + DayOfWeek.Saturday.toOrdinal();

        // We want divFloor because day -1 should map to week -1
        const week_num: i45 = @intCast(@divFloor(day_shifted, 7));

        return Week.from(week_num);
    }

    test fromDay {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(Week.from(0), Week.fromDay(Day.from(0)));
        try expectEqual(Week.from(0), Week.fromDay(Day.from(-5)));
        try expectEqual(Week.from(0), Week.fromDay(Day.from(1)));

        try expectEqual(Week.from(1), Week.fromDay(Day.from(2)));
        try expectEqual(Week.from(1), Week.fromDay(Day.from(8)));

        try expectEqual(Week.from(2), Week.fromDay(Day.from(9)));
        try expectEqual(Week.from(2), Week.fromDay(Day.from(15)));
    }

    pub fn toMonday(week: Week) Day {
        const week_num: i48 = week.to();
        const day_num = week_num * 7;
        const day_num_unshifted = day_num - DayOfWeek.Saturday.toOrdinal();
        return Day.from(day_num_unshifted);
    }

    test toMonday {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        const tst = struct {
            pub fn tst(d: i48, w: i45) !void {
                @disableInstrumentation();
                const day = Day.from(d);
                const week = Week.from(w);

                try expectEqual(day, week.toMonday());
            }
        }.tst;

        try tst(-5, 0);
        try tst(2, 1);
        try tst(9, 2);
        try tst(16, 3);
        try tst(23, 4);
        try tst(30, 5);
        try tst(37, 6);
    }

    pub fn to(week: Week) i45 {
        assert(week.isValid());

        return toUnchecked(week);
    }

    fn toUnchecked(week: Week) i45 {
        return @intFromEnum(week);
    }

    pub fn isValid(week: Week) bool {
        return week.toUnchecked() >= min.toUnchecked() and
            week.toUnchecked() <= max.toUnchecked();
    }

    pub fn firstDayOfWeek(week: Week) Day {
        // We need to cast up to avoid an integer overflow
        return Day.from(@as(i48, week.to()) * 7 - DayOfWeek.Saturday.toOrdinal());
    }

    test firstDayOfWeek {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(Day.from(-12), Week.from(-1).firstDayOfWeek());
        try expectEqual(Day.from(-5), Week.from(0).firstDayOfWeek());
        try expectEqual(Day.from(2), Week.from(1).firstDayOfWeek());

        for (1..1000) |week_idx| {
            // Week 1 starts at day 2, after that increment by 7 every time
            const day = Day.from(@intCast((week_idx - 1) * 7 + 2));
            const week = Week.from(@intCast(week_idx));
            try expectEqual(day, week.firstDayOfWeek());
        }
    }

    pub fn dayOfWeek(week: Week, day: DayOfWeek) Day {
        return Day.from(week.firstDayOfWeek().to() + day.toOrdinal());
    }

    test dayOfWeek {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(Day.from(0), Week.from(0).dayOfWeek(.Saturday));
        try expectEqual(Day.from(1), Week.from(0).dayOfWeek(.Sunday));
        try expectEqual(Day.from(-2), Week.from(0).dayOfWeek(.Thursday));
        try expectEqual(Day.from(5), Week.from(1).dayOfWeek(.Thursday));
    }

    /// Gets the day that contains this week. This is not equal to the year of
    /// the first day of the week.
    ///
    /// A week is contained in a year, if the thurday of the week is in that year.
    pub fn getYearContainingWeek(week: Week) Year {
        return Year.fromCalendarDay(week.dayOfWeek(.Thursday));
    }

    test getYearContainingWeek {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        // Since year 0 starts on a Saturday, week 0 actually starts in year
        // -1, funny stuff
        try expectEqual(Year.from(-1), Week.from(0).getYearContainingWeek());

        try expectEqual(52, Year.from(0).weeksInYear());
        try expectEqual(Year.from(0), Week.from(1).getYearContainingWeek());
        try expectEqual(Year.from(0), Week.from(52).getYearContainingWeek());

        try expectEqual(52, Year.from(1).weeksInYear());
        try expectEqual(Year.from(1), Week.from(53).getYearContainingWeek());
        try expectEqual(Year.from(1), Week.from(104).getYearContainingWeek());

        try expectEqual(52, Year.from(2).weeksInYear());
        try expectEqual(Year.from(2), Week.from(105).getYearContainingWeek());
        try expectEqual(Year.from(2), Week.from(156).getYearContainingWeek());

        try expectEqual(52, Year.from(3).weeksInYear());
        try expectEqual(Year.from(3), Week.from(157).getYearContainingWeek());
        try expectEqual(Year.from(3), Week.from(208).getYearContainingWeek());

        try expectEqual(53, Year.from(4).weeksInYear());
        try expectEqual(Year.from(4), Week.from(209).getYearContainingWeek());
        try expectEqual(Year.from(4), Week.from(261).getYearContainingWeek());

        try expectEqual(52, Year.from(5).weeksInYear());
        try expectEqual(Year.from(5), Week.from(262).getYearContainingWeek());
        try expectEqual(Year.from(5), Week.from(313).getYearContainingWeek());

        try expectEqual(Year.from(-1), Week.from(0).getYearContainingWeek());
        try expectEqual(Year.from(-1), Week.from(-51).getYearContainingWeek());

        try expectEqual(Year.from(-2), Week.from(-52).getYearContainingWeek());
        try expectEqual(Year.from(-2), Week.from(-104).getYearContainingWeek());

        try expectEqual(Year.from(-3), Week.from(-105).getYearContainingWeek());
        try expectEqual(Year.from(-3), Week.from(-156).getYearContainingWeek());
    }

    pub fn weekOfYear(week: Week) WeekOfYear {
        const year = week.getYearContainingWeek();
        const first_week_of_year = year.firstWeek();

        // If this ever fails, then getYearContainingWeek is incorrect
        assert(first_week_of_year.to() <= week.to());

        const week_in_year: u6 = @intCast(week.to() - first_week_of_year.to());

        return WeekOfYear.from0(week_in_year, year);
    }

    test weekOfYear {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(WeekOfYear.from(52, Year.from(-1)), Week.from(0).weekOfYear());

        try expectEqual(WeekOfYear.from(1, Year.from(0)), Week.from(1).weekOfYear());
        try expectEqual(WeekOfYear.from(52, Year.from(0)), Week.from(52).weekOfYear());

        try expectEqual(WeekOfYear.from(1, Year.from(1)), Week.from(53).weekOfYear());
        try expectEqual(WeekOfYear.from(52, Year.from(1)), Week.from(104).weekOfYear());

        try expectEqual(WeekOfYear.from(1, Year.from(2)), Week.from(105).weekOfYear());
        try expectEqual(WeekOfYear.from(52, Year.from(2)), Week.from(156).weekOfYear());

        try expectEqual(WeekOfYear.from(1, Year.from(3)), Week.from(157).weekOfYear());
        try expectEqual(WeekOfYear.from(52, Year.from(3)), Week.from(208).weekOfYear());

        try expectEqual(WeekOfYear.from(1, Year.from(4)), Week.from(209).weekOfYear());
        try expectEqual(WeekOfYear.from(53, Year.from(4)), Week.from(261).weekOfYear());
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.toUnchecked(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            try std.fmt.formatInt(value.toUnchecked(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

pub const WeekOfYear = enum(u6) {
    invalid = 0,
    _,

    pub const Error = error{UnrepresentableWeek};

    pub fn fromWeek(week: Week) WeekOfYear {
        return week.weekOfYear();
    }

    pub fn fromChecked(week: u6, year: Year) WeekOfYear {
        if (week < 1 or week >= year.weeksInYear())
            return Error.UnrepresentableWeek;

        return fromUnchecked(week);
    }

    pub fn from0(week: u6, year: Year) WeekOfYear {
        return WeekOfYear.from(week + 1, year);
    }

    pub fn from(week: u6, year: Year) WeekOfYear {
        const woy = fromUnchecked(week);

        assert(woy.isValid(year));

        return fromUnchecked(week);
    }

    fn fromUnchecked(week: u6) WeekOfYear {
        return @enumFromInt(week);
    }

    pub fn to0(week: WeekOfYear, year: Year) u6 {
        assert(week.isValid(year));

        return to0Unckecked(week);
    }

    fn to0Unckecked(week: WeekOfYear) u6 {
        return @intFromEnum(week) - 1;
    }

    pub fn to(week: WeekOfYear, year: Year) u6 {
        assert(week.isValid(year));

        return to0Unckecked(week);
    }

    fn toUnckecked(week: WeekOfYear) u6 {
        return @intFromEnum(week);
    }

    pub fn isValid(week: WeekOfYear, year: Year) bool {
        // We have 3 cases:
        // 1) the week is 1 <= week <= year.weeksInYear()
        // 2) we're in the last week of the previous year, AND
        //    the first few days of this year map to the last week
        //    of the previous year
        // 3) we're in the first week of next year, AND
        //    the last few days of this year map to the first week
        //    of the next year
        //
        // Since the third case would map {52,53} to 1, we can safely ignore
        // it. With the provided information we cannot differenciate this case,
        // and frankly I don't want this struct to depend on more than a year.
        const week_num = week.toUnckecked();

        if (1 <= week_num and week_num <= year.weeksInYear()) return true;

        const prev_year = year.tryPrev() catch return false;

        return week_num == prev_year.weeksInYear() and year.firstDay().isAfter(.Thursday);
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.to0Unckecked(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            try std.fmt.formatInt(value.toUnckecked(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

pub const Day = enum(i48) {
    _,

    pub const min = Day.fromUnchecked(-106751991166961);
    pub const max = Day.fromUnchecked(106751991166961);

    test "min/max" {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(date_min.getDay(), min);
        try expectEqual(date_max.getDay(), max);
    }

    pub const Error = error{UnrepresentableDay};

    pub fn from(day: i48) Day {
        assert(day <= max.to());
        assert(day >= min.to());

        return fromUnchecked(day);
    }

    pub fn fromChecked(day: i64) Error!Day {
        if (day > max.to() or day < min.to())
            return Error.UnrepresentableDay;

        return fromUnchecked(day);
    }

    pub fn fromUnchecked(oridnal_day: i48) Day {
        return @enumFromInt(oridnal_day);
    }

    pub fn to(day: Day) i48 {
        assert(day.isValid());

        return toUnchecked(day);
    }

    pub fn toUnchecked(day: Day) i48 {
        return @intFromEnum(day);
    }

    pub fn isValid(day: Day) bool {
        return day.toUnchecked() <= max.toUnchecked() and
            day.toUnchecked() >= min.toUnchecked();
    }
};

// One based representation of the day in a given year
pub const DayOfYear = enum(u9) {
    invalid = 0,
    _,

    pub const Error = error{UnrepresentableDay};

    pub fn fromSecondInYear(seconds_in_year: u25, is_leap_year: bool) DayOfYear {
        // We can use divTrunc, as we do not deal with negatives and second 1
        // should map to day 0
        return from0(@intCast(@divTrunc(seconds_in_year, s_per_day)), is_leap_year);
    }

    pub fn from0(day: u9, is_leap_year: bool) DayOfYear {
        return from(day +| 1, is_leap_year);
    }

    pub fn from(day: u9, is_leap_year: bool) DayOfYear {
        const doy = fromUnckecked(day);

        assert(doy.isValid(is_leap_year));

        return doy;
    }

    pub fn from0Checked(day: u9, is_leap_year: bool) Error!DayOfYear {
        return fromChecked(day + 1, is_leap_year);
    }

    pub fn fromChecked(day: u9, is_leap_year: bool) Error!DayOfYear {
        if (day < 1 or day > 365 + @as(u9, @intFromBool(is_leap_year)))
            return Error.UnrepresentableDay;

        return fromUnckecked(day);
    }

    fn fromUnckecked(day: u9) DayOfYear {
        return @enumFromInt(day);
    }

    pub fn to0(day_of_year: DayOfYear) u9 {
        return @intFromEnum(day_of_year) - 1;
    }

    pub fn to(day_of_year: DayOfYear) u9 {
        return @intFromEnum(day_of_year);
    }

    pub fn isValid(self: DayOfYear, is_leap_year: bool) bool {
        const max_ordinal_day = 365 + @as(u9, @intFromBool(is_leap_year));

        return self != .invalid and
            self.to() <= max_ordinal_day;
    }

    pub fn format(doy: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d:0>2}", .{@intFromEnum(doy)});
    }
};

pub const DayOfMonth = enum(u5) {
    invalid = 0,
    _,

    pub const Error = error{UnrepresentableDayOfMonth};

    pub fn fromOrdinal(day: u5, month: MonthOfYear, is_leap_year: bool) DayOfMonth {
        return from(day + 1, month, is_leap_year);
    }

    pub fn toOrdinal(day_of_month: DayOfMonth, month: MonthOfYear, is_leap_year: bool) u5 {
        return toRegularDay(day_of_month, month, is_leap_year) - 1;
    }

    pub fn toRegularDay(day_of_month: DayOfMonth, month: MonthOfYear, is_leap_year: bool) u5 {
        assert(day_of_month.isValid(month, is_leap_year));
        return day_of_month.toUnchecked();
    }

    pub fn toUnchecked(day_of_month: DayOfMonth) u5 {
        return @intFromEnum(day_of_month);
    }

    pub fn isValid(day_of_month: DayOfMonth, month: MonthOfYear, is_leap_year: bool) bool {
        return day_of_month != .invalid and
            day_of_month.toUnchecked() <= month.daysInMonth(is_leap_year);
    }

    pub fn from(day: u5, month: MonthOfYear, is_leap_year: bool) DayOfMonth {
        assert(day >= 1);
        assert(day <= month.daysInMonth(is_leap_year));

        return @enumFromInt(day);
    }

    pub fn fromChecked(day: u5, month: MonthOfYear, is_leap_year: bool) Error!DayOfMonth {
        if (day == 0 or day > month.daysInMonth(is_leap_year))
            return Error.UnrepresentableDayOfMonth;

        return @enumFromInt(day);
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.toUnchecked(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            try std.fmt.formatInt(value.toUnchecked(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

// FIXME: Reduce the usage of @intFromEnum
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

    pub const Error = error{
        UnrepresentableDay,
    };

    pub fn fromDay(day: Day) DayOfWeek {
        const week = Week.fromDay(day);
        const monday = week.toMonday();

        const dow: u3 = @intCast(day.to() - monday.to());
        return DayOfWeek.from0(dow);
    }

    test fromDay {
        @disableInstrumentation();

        const expectEqual = std.testing.expectEqual;

        try expectEqual(.Friday, DayOfWeek.fromDay(Day.from(-1)));
        try expectEqual(.Saturday, DayOfWeek.fromDay(Day.from(0)));
        try expectEqual(.Sunday, DayOfWeek.fromDay(Day.from(1)));
    }

    pub fn from0Checked(day: u3) Error!DayOfWeek {
        if (day >= 7) return Error.UnrepresentableDay;

        return DayOfWeek.from0(day);
    }

    pub fn from0(day: u3) DayOfWeek {
        return @enumFromInt(day + 1);
    }

    pub fn toOrdinal(day: DayOfWeek) u3 {
        return @intFromEnum(day) - 1;
    }

    // FIXME: Make this work with negatives too
    pub fn dowAfterNDays(dow: DayOfWeek, days: u45) DayOfWeek {
        const dow_num: u45 = dow.toOrdinal();
        const new_num = dow_num + days;
        const new_dow_ordinal: u3 = @intCast(@mod(new_num, 7));
        return DayOfWeek.from0(new_dow_ordinal);
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

    pub fn isBefore(day: DayOfWeek, reference: DayOfWeek) bool {
        return @intFromEnum(reference) > @intFromEnum(day);
    }

    pub fn isAfter(day: DayOfWeek, reference: DayOfWeek) bool {
        return @intFromEnum(reference) < @intFromEnum(day);
    }
};

pub const Hour = enum(u5) {
    _,

    pub const Error = error{UnrepresentableHour};

    pub fn from(hour: u5) Hour {
        assert(hour <= 24);

        return fromUnchecked(hour);
    }

    pub fn fromChecked(hour: u5) Error!Hour {
        if (hour > 24)
            return Error.UnrepresentableHour;

        return fromUnchecked(hour);
    }

    fn fromUnchecked(hour: u5) Hour {
        return @enumFromInt(hour);
    }

    pub fn to(hour: Hour) u5 {
        assert(hour.isValid());
        return toUnchecked(hour);
    }

    fn toUnchecked(hour: Hour) u5 {
        return @intFromEnum(hour);
    }

    pub fn isValid(hour: Hour) bool {
        return hour.toUnchecked() < 24;
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.to(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            try std.fmt.formatInt(value.to(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

pub const Minute = enum(u6) {
    _,

    pub const Error = error{UnrepresentableMinute};

    pub fn fromChecked(minute: u6) Error!Minute {
        if (minute >= 60)
            return Error.UnrepresentableMinute;

        return from(minute);
    }

    pub fn from(minute: u6) Minute {
        assert(minute < 60);

        return @enumFromInt(minute);
    }

    pub fn to(minute: Minute) u6 {
        assert(minute.isValid());
        return minute.toUnchecked();
    }

    fn toUnchecked(minute: Minute) u6 {
        return @intFromEnum(minute);
    }

    pub fn isValid(minute: Minute) bool {
        return minute.toUnchecked() < 60;
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.to(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            try std.fmt.formatInt(value.to(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

pub const Second = enum(u6) {
    _,

    pub const Error = error{UnrepresentableSecond};

    pub fn fromChecked(second: u6) Error!Second {
        // TODO: Leap seconds can get to 60, do we handle that here?
        //  - I say we handle that when formatting leap seconds
        if (second >= 60)
            return Error.UnrepresentableSecond;

        return from(second);
    }

    pub fn from(second: u6) Second {
        assert(second < 60);
        return @enumFromInt(second);
    }

    pub fn to(second: Second) u6 {
        assert(second.isValid());
        return toUnchecked(second);
    }

    fn toUnchecked(second: Second) u6 {
        return @intFromEnum(second);
    }

    pub fn isValid(second: Second) bool {
        return second.toUnchecked() < 60;
    }

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (std.mem.eql(u8, fmt, "any")) {
            try writer.writeAll(@typeName(@This()));
            try writer.writeAll("(");
            try std.fmt.formatInt(value.to(), 10, .lower, .{}, writer);
            try writer.writeAll(")");
        } else {
            try std.fmt.formatInt(value.to(), 10, .lower, .{
                .width = 2,
                .fill = '0',
                .alignment = .right,
            }, writer);
        }
    }
};

pub fn getCalendarDay(date: DateTime) Day {
    assert(date.isValid());
    return Day.from(@intCast(@divFloor(date.timestamp, s_per_day)));
}

test getCalendarDay {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    const tst = struct {
        pub fn tst(expected: i48, b: DateOptions) !void {
            @disableInstrumentation();
            const built = build(b);
            const expected_day = Day.from(expected);

            try expectEqual(expected_day, built.getCalendarDay());

            const built_start = build(.{
                .year = b.year,
                .month = b.month,
                .day_of_month = b.day_of_month,
                .hour = 0,
                .minute = 0,
                .second = 0,
            });

            try expectEqual(expected_day, built_start.getCalendarDay());

            const built_end = build(.{
                .year = b.year,
                .month = b.month,
                .day_of_month = b.day_of_month,
                .hour = 23,
                .minute = 59,
                .second = 59,
            });

            try expectEqual(expected_day, built_end.getCalendarDay());
        }
    }.tst;

    const tstraw = struct {
        pub fn tstraw(expected: i48, dt: DateTime) !void {
            const expected_day = Day.from(expected);

            try expectEqual(expected_day, dt.getCalendarDay());
        }
    }.tstraw;

    try tstraw(719_528, unixEpoch);
    try tstraw(0, gregorianEpoch);

    try tst(-1, .{ .year = -1, .month = .December, .day_of_month = 31 });
    try tst(-365, .{ .year = -1, .month = .January, .day_of_month = 1 });
}

pub fn getYear(date: DateTime) Year {
    assert(date.isValid());
    return Year.fromCalendarDay(date.getCalendarDay());
}

test getYear {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    const tst = struct {
        pub fn tst(b: DateOptions) !void {
            @disableInstrumentation();
            const built = build(b);
            const year = Year.from(b.year);

            try expectEqual(year, built.getYear());

            const built_start = build(.{
                .year = b.year,
                .month = .January,
                .day_of_month = 1,
                .hour = 0,
                .minute = 0,
                .second = 0,
            });

            try expectEqual(year, built_start.getYear());

            const built_end = build(.{
                .year = b.year,
                .month = .December,
                .day_of_month = 31,
                .hour = 23,
                .minute = 59,
                .second = 59,
            });

            try expectEqual(year, built_end.getYear());
        }
    }.tst;

    const tstraw = struct {
        pub fn tstraw(expected: i40, dt: DateTime) !void {
            @disableInstrumentation();
            const year = Year.from(expected);

            try expectEqual(year, dt.getYear());
        }
    }.tstraw;

    try tstraw(0, gregorianEpoch);
    try tstraw(1970, unixEpoch);

    try tstraw(-1, .{ .timestamp = -1 });

    try tst(.{ .year = 4 });
    try tst(.{ .year = -4 });

    try tst(.{ .year = 2024 });
    try tst(.{ .year = 2025 });
    try tst(.{ .year = 2000 });

    try tst(.{ .year = Year.min.to() });
    try tst(.{ .year = Year.max.to() });
}

pub fn getDayOfYear(date: DateTime) DayOfYear {
    assert(date.isValid());
    const year = date.getYear();

    const ordinal_days_to_ignore = year.daysSinceGregorianEpoch();

    const seconds_to_ignore = ordinal_days_to_ignore * s_per_day;

    const seconds_in_year: u25 = @intCast(date.timestamp - seconds_to_ignore);

    assert(seconds_in_year <= (@as(u25, year.getDaysInYear())) * s_per_day);
    assert(seconds_in_year >= 0);

    return DayOfYear.fromSecondInYear(seconds_in_year, year.isLeapYear());
}

test getDayOfYear {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    const tst = struct {
        pub fn tst(b: DateOptions) !void {
            @disableInstrumentation();
            const built = build(b);
            const year = Year.from(b.year);
            const is_leap = year.isLeapYear();
            const expected_day = b.month.ordinalNumberOfFirstOfMonth(is_leap) +
                b.day_of_month;

            try expectEqual(DayOfYear.from(expected_day, is_leap), built.getDayOfYear());
        }
    }.tst;

    // Around 0
    try tst(.{ .year = 0 });
    try tst(.{ .year = 0, .month = .December, .day_of_month = 31 });
    try tst(.{ .year = 0, .month = .February, .day_of_month = 29 });

    // Positives
    try tst(.{ .year = 1_000_000_123 });
    try tst(.{ .year = 1_000_000_123, .month = .December, .day_of_month = 31 });
    try tst(.{ .year = 1_000_000_123, .month = .February, .day_of_month = 28 });

    // Positive leap years
    try tst(.{ .year = 1_000_000_000 });
    try tst(.{ .year = 1_000_000_000, .month = .December, .day_of_month = 31 });
    try tst(.{ .year = 1_000_000_000, .month = .February, .day_of_month = 29 });

    // Negatives
    try tst(.{ .year = -1_000_000_123 });
    try tst(.{ .year = -1_000_000_123, .month = .December, .day_of_month = 31 });
    try tst(.{ .year = -1_000_000_123, .month = .February, .day_of_month = 28 });

    // Negative leap years
    try tst(.{ .year = -4 });
    try tst(.{ .year = -4, .month = .December, .day_of_month = 31 });
    try tst(.{ .year = -4, .month = .February, .day_of_month = 29 });

    try tst(.{ .year = Year.min.to() });
    try tst(.{ .year = Year.max.to() });

    const tstraw = struct {
        pub fn tstraw(expected: u9, dt: DateTime) !void {
            @disableInstrumentation();
            try expectEqual(DayOfYear.from(expected, true), dt.getDayOfYear());
        }
    }.tstraw;

    try tstraw(365, .{ .timestamp = -1 });

    // From fuzzer
    try tstraw(365, DateTime{ .timestamp = -8364670018373460762 });
    try tstraw(1, DateTime{ .timestamp = -8364670018373289601 });
    try tstraw(2, DateTime{ .timestamp = -8364670018373289600 });
}

pub fn getMonth(date: DateTime) MonthOfYear {
    assert(date.isValid());
    return MonthOfYear.fromCalendarDayOfYear(
        date.getDayOfYear(),
        date.getYear().isLeapYear(),
    );
}

test getMonth {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    const tst = struct {
        pub fn tst(month: MonthOfYear, b: DateOptions) !void {
            @disableInstrumentation();
            const date = build(b);
            const date_start = build(.{
                .year = b.year,
                .month = b.month,
                .day_of_month = 1,
            });
            const date_end = build(.{
                .year = b.year,
                .month = b.month,
                .day_of_month = b.month.daysInMonth(Year.from(b.year).isLeapYear()),
                .hour = 23,
                .minute = 59,
                .second = 59,
            });

            try expectEqual(month, date.getMonth());
            try expectEqual(month, date_start.getMonth());
            try expectEqual(month, date_end.getMonth());
        }
    }.tst;

    try tst(.January, .{ .year = -1, .month = .January });
    try tst(.January, .{ .year = 0, .month = .January });
    try tst(.January, .{ .year = 1, .month = .January });
    try tst(.January, .{ .year = 1970, .month = .January });
    try tst(.January, .{ .year = 2000, .month = .January });
    try tst(.January, .{ .year = 2024, .month = .January });
    try tst(.January, .{ .year = 2100, .month = .January });
}

pub fn getDayOfMonth(date: DateTime) DayOfMonth {
    assert(date.isValid());
    const year = date.getYear();
    const month = date.getMonth();
    const day_of_year = date.getDayOfYear();
    return month.calendarDayOfMonth(year.isLeapYear(), day_of_year);
}

test getDayOfMonth {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    var date_pos = gregorianEpoch;
    for (1..@as(u6, MonthOfYear.January.daysInMonth(true)) + 1) |i| {
        try expectEqual(DayOfMonth.from(@intCast(i), .January, true), date_pos.getDayOfMonth());
        date_pos = date_pos.addDays(1);
    }
    try expectEqual(DayOfMonth.from(1, .January, true), date_pos.getDayOfMonth());

    var date_neg = gregorianEpoch;
    date_neg = date_neg.addSeconds(-1);
    for (0..31) |i| {
        const day = 31 - i;
        try expectEqual(DayOfMonth.from(@intCast(day), .December, true), date_neg.getDayOfMonth());
        date_neg = date_neg.addDays(-1);
    }
    try expectEqual(DayOfMonth.from(30, .November, true), date_neg.getDayOfMonth());
}

pub fn getWeek(date: DateTime) Week {
    assert(date.isValid());
    // divFloor verified through test cases
    return Week.from(@intCast(@divFloor(date.timestamp, s_per_week)));
}

test getWeek {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    try expectEqual(Week.from(0), gregorianEpoch.addSeconds(0).getWeek());
    try expectEqual(Week.from(1), gregorianEpoch.addSeconds(s_per_week).getWeek());
    try expectEqual(Week.from(-1), gregorianEpoch.addSeconds(-1).getWeek());
    try expectEqual(Week.from(-1), gregorianEpoch.addSeconds(-s_per_week).getWeek());
    try expectEqual(Week.from(-2), gregorianEpoch.addSeconds(-s_per_week - 1).getWeek());
}

pub fn getWeekOfYear(date: DateTime) WeekOfYear {
    assert(date.isValid());
    return WeekOfYear.fromWeek(date.getWeek());
}

test getWeekOfYear {
    @disableInstrumentation();

    const date = DateTime.build(.{ .year = -35, .day_of_month = 2 });
    _ = date.getWeekOfYear();
}

pub fn getDayOfWeek(date: DateTime) DayOfWeek {
    return DayOfWeek.fromDay(date.getDay());
}

pub fn getDay(date: DateTime) Day {
    assert(date.isValid());
    // divFloor verified through test cases
    return Day.from(@intCast(@divFloor(date.timestamp, s_per_day)));
}

test getDay {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    try expectEqual(Day.from(0), gregorianEpoch.addSeconds(0).getDay());
    try expectEqual(Day.from(1), gregorianEpoch.addSeconds(86400).getDay());
    try expectEqual(Day.from(-1), gregorianEpoch.addSeconds(-1).getDay());
    try expectEqual(Day.from(-1), gregorianEpoch.addSeconds(-86400).getDay());
    try expectEqual(Day.from(-2), gregorianEpoch.addSeconds(-86401).getDay());
}

pub fn getHour(date: DateTime) Hour {
    assert(date.isValid());
    // divTrunc verified through test cases
    return Hour.from(@intCast(@divTrunc(@mod(date.timestamp, s_per_day), s_per_hour)));
}

test getHour {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    try expectEqual(Hour.from(0), gregorianEpoch.addSeconds(0).getHour());
    try expectEqual(Hour.from(1), gregorianEpoch.addSeconds(3600).getHour());
    try expectEqual(Hour.from(23), gregorianEpoch.addSeconds(-1).getHour());
    try expectEqual(Hour.from(23), gregorianEpoch.addSeconds(-3600).getHour());
    try expectEqual(Hour.from(22), gregorianEpoch.addSeconds(-3601).getHour());
}

pub fn getMinute(date: DateTime) Minute {
    assert(date.isValid());
    // divTrunc verified through test cases
    return Minute.from(@intCast(@divTrunc(@mod(date.timestamp, s_per_hour), s_per_min)));
}

test getMinute {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    try expectEqual(Minute.from(0), gregorianEpoch.addSeconds(0).getMinute());
    try expectEqual(Minute.from(1), gregorianEpoch.addSeconds(60).getMinute());
    try expectEqual(Minute.from(59), gregorianEpoch.addSeconds(-1).getMinute());
    try expectEqual(Minute.from(59), gregorianEpoch.addSeconds(-60).getMinute());
    try expectEqual(Minute.from(58), gregorianEpoch.addSeconds(-61).getMinute());
}

pub fn getSecond(date: DateTime) Second {
    assert(date.isValid());
    return Second.from(@intCast(@mod(date.timestamp, s_per_min)));
}

pub const DateOptions = struct {
    year: i40,
    month: MonthOfYear = .January,
    day_of_month: u5 = 1,
    hour: u5 = 0,
    minute: u6 = 0,
    second: u6 = 0,
};

pub const DateOptionsTyped = struct {
    year: Year,
    month: MonthOfYear,
    day_of_month: DayOfMonth,
    hour: Hour,
    minute: Minute,
    second: Second,
};

pub fn buildTyped(b: DateOptionsTyped) DateTime {
    return DateTime.gregorianEpoch
        .setYear(b.year)
        .addDays(b.month.ordinalNumberOfFirstOfMonth(b.year.isLeapYear()))
        .addDays(b.day_of_month.toOrdinal(b.month, b.year.isLeapYear()))
        .addHours(b.hour.to())
        .addMinutes(b.minute.to())
        .addSeconds(b.second.to());
}

test buildTyped {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    try expectEqual(unixEpoch, buildTyped(.{
        .year = Year.from(1970),
        .month = .January,
        .day_of_month = DayOfMonth.from(1, .January, false),
        .hour = Hour.from(0),
        .minute = Minute.from(0),
        .second = Second.from(0),
    }));
}

// TODO: Figure out how I want to combine checked and non checked functions to
// share the same code. Them all being duplicates is just asking for bugs

/// Date build function meant to be used in code to create a date in a human
/// readable way.
pub fn build(b: DateOptions) DateTime {
    const year = Year.from(b.year);
    const day_of_month_cast = DayOfMonth.from(b.day_of_month, b.month, year.isLeapYear());

    return buildTyped(.{
        .year = year,
        .month = b.month,
        .day_of_month = day_of_month_cast,
        .hour = Hour.from(b.hour),
        .minute = Minute.from(b.minute),
        .second = Second.from(b.second),
    });
}

pub fn buildChecked(b: DateOptions) !DateTime {
    const year = try Year.fromChecked(b.year);
    const day_of_month_cast = try DayOfMonth.fromChecked(b.day_of_month, b.month, year.isLeapYear());

    return buildTyped(.{
        .year = year,
        .month = b.month,
        .day_of_month = day_of_month_cast,
        .hour = try Hour.fromChecked(b.hour),
        .minute = try Minute.fromChecked(b.minute),
        .second = try Second.fromChecked(b.second),
    });
}

test build {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    try expectEqual(unixEpoch, build(.{ .year = 1970, .month = .January, .day_of_month = 1 }));
    try expectEqual(gregorianEpoch, build(.{ .year = 0, .month = .January, .day_of_month = 1 }));

    try expectEqual(gregorianEpoch.addYears(-1), build(.{ .year = -1, .month = .January, .day_of_month = 1 }));
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
    assert(date.isValid());
    assert(year.isValid());

    const ordinal_feb29 = comptime MonthOfYear.February.ordinalNumberOfFirstOfMonth(true) + 29;

    const ordinal_day_of_year = blk: {
        const orig_day_of_year = date.getDayOfYear().to0();

        break :blk orig_day_of_year -
            @intFromBool(date.getYear().isLeapYear() and !year.isLeapYear() and orig_day_of_year >= ordinal_feb29) +
            @intFromBool(!date.getYear().isLeapYear() and year.isLeapYear() and orig_day_of_year >= ordinal_feb29);
    };

    const days_to_jan1_of_year = year.daysSinceGregorianEpoch();

    return gregorianEpoch.addDays(days_to_jan1_of_year + ordinal_day_of_year);
}

test setYear {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    const last_day_of_leap = build(.{ .year = 2000, .month = .December, .day_of_month = 31 });
    const last_day_of_regular = build(.{ .year = 2001, .month = .December, .day_of_month = 31 });
    assert(366 == last_day_of_leap.getDayOfYear().to());
    assert(365 == last_day_of_regular.getDayOfYear().to());

    try expectEqual(DayOfYear.from(366, true), last_day_of_leap.setYear(Year.from(2024)).getDayOfYear());
    try expectEqual(DayOfYear.from(365, false), last_day_of_leap.setYear(Year.from(2001)).getDayOfYear());

    try expectEqual(DayOfYear.from(365, false), last_day_of_regular.setYear(Year.from(2002)).getDayOfYear());
    try expectEqual(DayOfYear.from(366, true), last_day_of_regular.setYear(Year.from(2004)).getDayOfYear());

    const tst = struct {
        pub fn tst(year: Year) !void {
            @disableInstrumentation();
            const gregorian = gregorianEpoch.setYear(year);
            const unix = unixEpoch.setYear(year);

            try expectEqual(DayOfYear.from(1, false), gregorian.getDayOfYear());
            try expectEqual(year, gregorian.getYear());

            try expectEqual(DayOfYear.from(1, false), unix.getDayOfYear());
            try expectEqual(year, unix.getYear());
        }
    }.tst;

    for (0..500) |year| {
        try tst(Year.from(@intCast(year)));
        try tst(Year.from(-@as(i40, @intCast(year))));
    }
}

pub fn addYearsChecked(date: DateTime, years: i40) !DateTime {
    if (!date.isValid()) return error.InvalidDateTime;

    const year = try Year.fromChecked(date.getYear().to() +| years);

    return gregorianEpoch.setYear(year);
}

pub fn addYears(date: DateTime, years: i40) DateTime {
    assert(date.isValid());
    const year = Year.from(date.getYear().to() +| years);

    return gregorianEpoch.setYear(year);
}

test addYears {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    for (1..100) |year_step| {
        var date = gregorianEpoch;

        for (0..1000) |i| {
            const expected_year = year_step * i;

            try expectEqual(DayOfYear.from0(0, false), date.getDayOfYear());
            try expectEqual(MonthOfYear.January, date.getMonth());
            try expectEqual(Year.from(@intCast(expected_year)), date.getYear());

            date = date.addYears(@intCast(year_step));
        }
    }
}

pub fn addMonthsChecked(date: DateTime, months: i40) !DateTime {
    if (!date.isValid()) return error.UnrepresentableDate;

    const day_of_month = date.getDayOfMonth();

    // We want divTrunc, as -1 month does not mean go back 1 year
    const years_to_add = try Year.fromChecked(@intCast(@divTrunc(months, 12)));
    const months_to_add = @rem(months, 12);
    const month_ordial = date.getMonth().to0();

    const new_month_ordinal: u4 = @intCast(@mod(month_ordial + months_to_add, 12));

    // We want divFloor because -1 month means we overflowed 1 month into the
    // previous year
    const years_overflowed = try Year.fromChecked(@intCast(@divFloor(month_ordial + months_to_add, 12)));
    const new_year = try Year.fromChecked(date.getYear().to() +
        years_to_add.to() +
        years_overflowed.to());

    const new_month, const new_day_of_month = blk: {
        const guessed_month = MonthOfYear.from0(new_month_ordinal);

        if (guessed_month.daysInMonth(new_year.isLeapYear()) >= day_of_month.toUnchecked()) {
            // The day_of_month fits inside our guessed month, we're good
            break :blk .{ guessed_month, day_of_month };
        }

        // day_of_month does _not_ fit inside guessed month, we're 1 month off
        const new_month = guessed_month.next();
        const new_day_of_month = DayOfMonth.from(
            day_of_month.toUnchecked() - guessed_month.daysInMonth(new_year.isLeapYear()),
            new_month,
            new_year.isLeapYear(),
        );

        break :blk .{ new_month, new_day_of_month };
    };

    return DateTime.gregorianEpoch
        .setYear(new_year)
        .addDays(new_month.ordinalNumberOfFirstOfMonth(new_year.isLeapYear()))
        .addDays(new_day_of_month.toOrdinal(new_month, new_year.isLeapYear()));
}

pub fn addMonths(date: DateTime, months: i40) DateTime {
    return date.addMonthsChecked(months) catch unreachable;
}

test addMonths {
    @disableInstrumentation();

    const expectEqual = std.testing.expectEqual;

    const tst = struct {
        pub fn tst(add: i40, s: DateOptions, e: DateOptions) !void {
            @disableInstrumentation();
            const start = build(s);
            const end = build(e);

            const actual = start.addMonths(add);

            try expectEqual(end, actual);
        }
    }.tst;

    try tst(
        1,
        .{ .year = 0, .month = .December, .day_of_month = 31 },
        .{ .year = 1, .month = .January, .day_of_month = 31 },
    );

    try tst(
        -1,
        .{ .year = 0, .month = .January, .day_of_month = 31 },
        .{ .year = -1, .month = .December, .day_of_month = 31 },
    );

    try tst(
        1,
        .{ .year = 2020, .month = .January, .day_of_month = 1 },
        .{ .year = 2020, .month = .February, .day_of_month = 1 },
    );

    try tst(
        1,
        .{ .year = 2019, .month = .December, .day_of_month = 1 },
        .{ .year = 2020, .month = .January, .day_of_month = 1 },
    );

    try tst(
        -1,
        .{ .year = 2020, .month = .January, .day_of_month = 1 },
        .{ .year = 2019, .month = .December, .day_of_month = 1 },
    );

    // Non trivial day_of_month
    try tst(
        2,
        .{ .year = 2019, .month = .November, .day_of_month = 30 },
        .{ .year = 2020, .month = .January, .day_of_month = 30 },
    );

    try tst(
        -2,
        .{ .year = 2020, .month = .January, .day_of_month = 30 },
        .{ .year = 2019, .month = .November, .day_of_month = 30 },
    );

    // Funky cases (I hate months)
    try tst(
        1,
        .{ .year = 2020, .month = .January, .day_of_month = 31 },
        .{ .year = 2020, .month = .March, .day_of_month = 2 },
    );

    try tst(
        13,
        .{ .year = 2019, .month = .January, .day_of_month = 31 },
        .{ .year = 2020, .month = .March, .day_of_month = 2 },
    );

    try tst(
        1,
        .{ .year = 2021, .month = .January, .day_of_month = 31 },
        .{ .year = 2021, .month = .March, .day_of_month = 3 },
    );

    try tst(
        13,
        .{ .year = 2020, .month = .January, .day_of_month = 31 },
        .{ .year = 2021, .month = .March, .day_of_month = 3 },
    );

    try tst(
        2,
        .{ .year = 2020, .month = .January, .day_of_month = 31 },
        .{ .year = 2020, .month = .March, .day_of_month = 31 },
    );

    try tst(
        14,
        .{ .year = 2019, .month = .January, .day_of_month = 31 },
        .{ .year = 2020, .month = .March, .day_of_month = 31 },
    );
}

pub fn addWeeksChecked(date: DateTime, weeks: i64) !DateTime {
    return date.addSecondsChecked(weeks *| s_per_week);
}

pub fn addWeeks(date: DateTime, weeks: i64) DateTime {
    assert(date.isValid());
    return .{
        .timestamp = date.timestamp + weeks * s_per_week,
    };
}

pub fn addDaysChecked(date: DateTime, days: i64) !DateTime {
    return date.addSecondsChecked(days *| s_per_day);
}

pub fn addDays(date: DateTime, days: i64) DateTime {
    assert(date.isValid());
    return .{
        .timestamp = date.timestamp + days * s_per_day,
    };
}

pub fn addHoursChecked(date: DateTime, hours: i64) !DateTime {
    return date.addSecondsChecked(hours *| s_per_hour);
}

pub fn addHours(date: DateTime, hours: i64) DateTime {
    assert(date.isValid());
    return .{
        .timestamp = date.timestamp + hours * s_per_hour,
    };
}

pub fn addMinutesChecked(date: DateTime, minutes: i64) !DateTime {
    return date.addSecondsChecked(minutes *| s_per_min);
}

pub fn addMinutes(date: DateTime, minutes: i64) DateTime {
    assert(date.isValid());
    return .{
        .timestamp = date.timestamp + minutes * s_per_min,
    };
}

pub fn addSecondsChecked(date: DateTime, seconds: i64) !DateTime {
    if (!date.isValid()) return error.InvalidDateTime;

    const new_timestamp, const overflow = @addWithOverflow(date.timestamp, seconds);

    if (overflow != 0) return error.UnrepresentableDateTime;

    return .{ .timestamp = new_timestamp };
}

// FIXME: This should assert the returned date is valid too
pub fn addSeconds(date: DateTime, seconds: i64) DateTime {
    assert(date.isValid());
    return .{
        .timestamp = date.timestamp + seconds,
    };
}

pub fn toUnixTimestamp(date: DateTime) i64 {
    return date.timestamp - DateTime.unixEpoch.timestamp;
}

pub fn isValid(date: DateTime) bool {
    return date.timestamp >= date_min.timestamp and
        date.timestamp <= date_max.timestamp;
}

pub fn format(date: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = options;

    if (!date.isValid()) {
        return std.fmt.format(writer, "Invalid Date ({d})", .{date.timestamp});
    }

    if (std.mem.eql(u8, fmt, "d")) {
        return std.fmt.format(
            writer,
            "{s}({d})",
            .{ @typeName(@This()), date.timestamp },
        );
    }

    try std.fmt.format(
        writer,
        "{}-{}-{}T{}:{}:{}",
        .{
            date.getYear(),
            date.getMonth(),
            date.getDayOfMonth(),
            date.getHour(),
            date.getMinute(),
            date.getSecond(),
        },
    );
}

test format {
    @disableInstrumentation();

    const nullWriter = std.io.null_writer;

    _ = try std.fmt.format(nullWriter, "{}", .{gregorianEpoch});
    _ = try std.fmt.format(nullWriter, "{}", .{date_min});
    _ = try std.fmt.format(nullWriter, "{}", .{date_max});
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

test {
    @disableInstrumentation();

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

const fuzz = @import("fuzz.zig");
test "Fuzz Years" {
    @disableInstrumentation();

    try std.testing.fuzz(fuzz.fuzzYears, .{});
}
test "Fuzz Set Years" {
    @disableInstrumentation();

    try std.testing.fuzz(fuzz.fuzzSetYears, .{});
}
test "Fuzz Months" {
    @disableInstrumentation();

    try std.testing.fuzz(fuzz.fuzzMonths, .{});
}
test "Fuzz Constants" {
    @disableInstrumentation();

    try std.testing.fuzz(fuzz.fuzzConstants, .{});
}
test "Fuzz Getters" {
    @disableInstrumentation();

    try std.testing.fuzz(fuzz.fuzzGetters, .{});
}
test "Fuzz format" {
    @disableInstrumentation();

    try std.testing.fuzz(fuzz.fuzzFormat, .{});
}
test "Fuzz validate" {
    @disableInstrumentation();

    try std.testing.fuzz(fuzz.fuzzValidate, .{});
}
