fn getDate(r: Random) DateTime {
    return .{
        .timestamp = r.intRangeAtMostBiased(
            i64,
            DateTime.date_min.timestamp,
            DateTime.date_max.timestamp,
        ),
    };
}
pub fn fuzzYears(input: []const u8) !void {
    const seed: u64 = if (input.len >= 8)
        @bitCast(input[0..8].*)
    else blk: {
        var seed_buf: [8]u8 = undefined;
        @memcpy(seed_buf[0..input.len], input[0..]);
        break :blk @bitCast(seed_buf);
    };

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const date = getDate(random);

    const max_year = Year.max.to() -| date.getYear().to();
    const min_year = Year.min.to() -| date.getYear().to();
    _ = try date.addYearsChecked(random.intRangeAtMostBiased(i40, min_year, max_year));
}

pub fn fuzzSetYears(input: []const u8) !void {
    const seed: u64 = if (input.len >= 8)
        @bitCast(input[0..8].*)
    else blk: {
        var seed_buf: [8]u8 = undefined;
        @memcpy(seed_buf[0..input.len], input[0..]);
        break :blk @bitCast(seed_buf);
    };

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const date = getDate(random);

    const set_target = random.intRangeAtMostBiased(i40, Year.min.to(), Year.max.to());
    const set_year = try Year.fromChecked(set_target);

    const new_date = date.setYear(set_year);

    const expectEqual = std.testing.expectEqual;
    try expectEqual(set_year, new_date.getYear());

    // Don't bother checking if dates are not both {leap,regular} years. Too complex
    if (date.getYear().isLeapYear() == new_date.getYear().isLeapYear()) {
        // Both leap or both non leap
        try expectEqual(date.getDayOfYear(), new_date.getDayOfYear());
    }
}

pub fn fuzzGetDayOfYear(input: []const u8) !void {
    const seed: u64 = if (input.len >= 8)
        @bitCast(input[0..8].*)
    else blk: {
        var seed_buf: [8]u8 = undefined;
        @memcpy(seed_buf[0..input.len], input[0..]);
        break :blk @bitCast(seed_buf);
    };

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const date = getDate(random);

    _ = date.getDayOfYear();
}

pub fn fuzzMonths(input: []const u8) !void {
    const seed: u64 = if (input.len >= 8)
        @bitCast(input[0..8].*)
    else blk: {
        var seed_buf: [8]u8 = undefined;
        @memcpy(seed_buf[0..input.len], input[0..]);
        break :blk @bitCast(seed_buf);
    };

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const date = getDate(random);
    _ = date.addMonthsChecked(random.int(i40)) catch return;
}

pub fn fuzzConstants(input: []const u8) !void {
    const seed: u64 = if (input.len >= 8)
        @bitCast(input[0..8].*)
    else blk: {
        var seed_buf: [8]u8 = undefined;
        @memcpy(seed_buf[0..input.len], input[0..]);
        break :blk @bitCast(seed_buf);
    };

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const date = getDate(random);
    _ = date.addSecondsChecked(random.int(i64)) catch return;
    _ = date.addMinutesChecked(random.int(i64)) catch return;
    _ = date.addHoursChecked(random.int(i64)) catch return;
    _ = date.addDaysChecked(random.int(i64)) catch return;
    _ = date.addWeeksChecked(random.int(i64)) catch return;
}

pub fn fuzzGetters(input: []const u8) !void {
    const seed: u64 = if (input.len >= 8)
        @bitCast(input[0..8].*)
    else blk: {
        var seed_buf: [8]u8 = undefined;
        @memcpy(seed_buf[0..input.len], input[0..]);
        break :blk @bitCast(seed_buf);
    };

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const date = getDate(random);
    _ = date.getYear();
    _ = date.getDayOfYear();
    _ = date.getMonth();
    _ = date.getDayOfMonth();
    _ = date.getWeek();
    _ = date.getDay();
    _ = date.getHour();
    _ = date.getMinute();
    _ = date.getSecond();

    try std.fmt.format(std.io.null_writer, "{}", .{date});
}

const std = @import("std");
const Random = std.Random;
const DateTime = @import("DateTime.zig");
const Year = DateTime.Year;
