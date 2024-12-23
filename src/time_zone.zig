pub const UtcOptions = struct {
    /// An hour offset between -12 and +14
    hour: i6 = 0,
    /// A minute offset between 0 and 60
    minute: u7 = 0,
};
pub fn utc(date: DateTime, opt: UtcOptions) DateTime {
    assert(opt.minute <= 60);
    assert(-12 <= opt.hour and opt.hour <= 14);

    const offset = @as(i64, opt.hour) * std.time.s_per_hour +
        @as(i64, opt.minute) * std.time.s_per_min;

    return date.addSeconds(offset);
}

const LeapSecond = struct { Year, i2, i2 };

/// All leap seconds between 1972 and 2024
const leap_seconds: []const LeapSecond = &.{
    .{ Year.from(1972), 1, 1 },
    .{ Year.from(1973), 0, 1 },
    .{ Year.from(1974), 0, 1 },
    .{ Year.from(1975), 0, 1 },
    .{ Year.from(1976), 0, 1 },
    .{ Year.from(1977), 0, 1 },
    .{ Year.from(1978), 0, 1 },
    .{ Year.from(1979), 0, 1 },
    // .{Year.from(1980), 0, 0},
    .{ Year.from(1981), 1, 0 },
    .{ Year.from(1982), 1, 0 },
    .{ Year.from(1983), 1, 0 },
    // .{Year.from(1984), 0, 0},
    .{ Year.from(1985), 1, 0 },
    // .{Year.from(1986), 0, 0},
    .{ Year.from(1987), 0, 1 },
    .{ Year.from(1988), 0, 0 },
    .{ Year.from(1989), 0, 1 },
    .{ Year.from(1990), 0, 1 },
    // .{Year.from(1991), 0, 0},
    .{ Year.from(1992), 1, 0 },
    .{ Year.from(1993), 1, 0 },
    .{ Year.from(1994), 1, 0 },
    .{ Year.from(1995), 0, 1 },
    // .{Year.from(1996), 0, 0},
    .{ Year.from(1997), 1, 0 },
    .{ Year.from(1998), 0, 1 },
    // .{Year.from(1999), 0, 0},
    // .{Year.from(2000), 0, 0},
    // .{Year.from(2001), 0, 0},
    // .{Year.from(2002), 0, 0},
    // .{Year.from(2003), 0, 0},
    // .{Year.from(2004), 0, 0},
    .{ Year.from(2005), 0, 1 },
    // .{Year.from(2006), 0, 0},
    // .{Year.from(2007), 0, 0},
    .{ Year.from(2008), 0, 1 },
    // .{Year.from(2009), 0, 0},
    // .{Year.from(2010), 0, 0},
    // .{Year.from(2011), 0, 0},
    .{ Year.from(2012), 1, 0 },
    // .{Year.from(2013), 0, 0},
    // .{Year.from(2014), 0, 0},
    .{ Year.from(2015), 1, 0 },
    .{ Year.from(2016), 0, 1 },
    // .{Year.from(2017), 0, 0},
    // .{Year.from(2018), 0, 0},
    // .{Year.from(2019), 0, 0},
    // .{Year.from(2020), 0, 0},
    // .{Year.from(2021), 0, 0},
    // .{Year.from(2022), 0, 0},
    // .{Year.from(2023), 0, 0},
    // .{Year.from(2024), 0, 0},
};

pub fn applyLeapSeconds(date: DateTime) DateTime {
    var updated_date = date;
    for (leap_seconds) |item| {
        const y: Year = item.@"0";

        const jun30 = build(.{
            .year = y,
            .month = .June,
            .day_of_month = DayOfMonth.from(30, .june, y.isLeapYear()),
            .hour = Hour.from(23),
            .minute = Minute.from(59),
            .second = Second.from(59),
        });

        if (!date.isAfter(jun30)) return updated_date;
        updated_date.addSeconds(item.@"1");

        const dec30 = build(.{
            .year = y,
            .month = .June,
            .day_of_month = DayOfMonth.from(30, .june, y.isLeapYear()),
            .hour = Hour.from(23),
            .minute = Minute.from(59),
            .second = Second.from(59),
        });

        if (!date.isAfter(dec30)) return updated_date;
        updated_date.addSeconds(item.@"2");
    }

    return updated_date;
}

const DateTime = @import("DateTime.zig");
const Year = DateTime.Year;
const DayOfMonth = DateTime.DayOfMonth;
const Hour = DateTime.Hour;
const Minute = DateTime.Minute;
const Second = DateTime.Second;
const build = DateTime.buildTyped;
const std = @import("std");
const assert = std.debug.assert;
