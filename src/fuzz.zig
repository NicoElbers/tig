fn getDate(r: Random) DateTime {
    const date: DateTime = .{ .timestamp = r.int(i64) };
    std.debug.print("Date: {any}\n", .{date});
    return date;
}

fn getValidDate(r: Random) DateTime {
    const date = DateTime.fromGregorianTimestamp(r.intRangeAtMostBiased(
        i64,
        DateTime.date_min.timestamp,
        DateTime.date_max.timestamp,
    ));
    std.debug.print("Date: {any}\n", .{date});
    return date;
}

fn getYear(r: Random) Year {
    const year: Year = @enumFromInt(r.int(i64));
    std.debug.print("Year: {any}\n", .{year});
    return year;
}

fn getValidYear(r: Random) Year {
    const year = Year.from(r.intRangeAtMostBiased(i40, Year.min.to(), Year.max.to()));
    std.debug.print("Year: {any}\n", .{year});
    return year;
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

    {
        const max_year = Year.max.to() -| date.getYear().to();
        const min_year = Year.min.to() -| date.getYear().to();
        const y = try date.addYearsChecked(random.intRangeAtMostBiased(i40, min_year, max_year));
        _ = y.getYear();
    }
    {
        const set = getValidYear(random);
        const d = DateTime.gregorianEpoch.addYears(set.to());
        const get = d.getYear();
        try expectEqual(set, get);
    }
    blk: {
        const d = DateTime.gregorianEpoch.addYearsChecked(@intFromEnum(getYear(random))) catch break :blk;
        try expect(d.isValid());
    }
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

    try expectEqual(set_year, new_date.getYear());

    // Don't bother checking if dates are not both {leap,regular} years.
    // Too complex to fuzz
    if (date.getYear().isLeapYear() == new_date.getYear().isLeapYear()) {
        // Both leap or both non leap
        try expectEqual(date.getDayOfYear(), new_date.getDayOfYear());
    }
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

    blk: {
        const date = getDate(random);
        const d = date.addMonthsChecked(random.int(i40)) catch break :blk;
        try expect(d.isValid());
    }
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
    blk: {
        const d = date.addSecondsChecked(random.int(i64)) catch break :blk;
        try expect(d.isValid());
    }
    blk: {
        const d = date.addMinutesChecked(random.int(i64)) catch break :blk;
        try expect(d.isValid());
    }
    blk: {
        const d = date.addHoursChecked(random.int(i64)) catch break :blk;
        try expect(d.isValid());
    }
    blk: {
        const d = date.addDaysChecked(random.int(i64)) catch break :blk;
        try expect(d.isValid());
    }
    blk: {
        const d = date.addWeeksChecked(random.int(i64)) catch break :blk;
        try expect(d.isValid());
    }
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

    const date = getValidDate(random);
    {
        const o = date.getYear();
        try expect(o.isValid());
    }
    {
        const o = date.getDayOfYear();
        std.debug.print("Year: {}; doy: {d}; date: {}\n", .{ date.getYear(), @intFromEnum(o), date });
        try expect(o.isValid(date.getYear().isLeapYear()));
    }
    {
        // Month is exhaustive, and cannot be invalid
        _ = date.getMonth();
    }
    {
        const o = date.getDayOfMonth();
        try expect(o.isValid(date.getMonth(), date.getYear().isLeapYear()));
    }
    {
        const o = date.getWeek();
        try expect(o.isValid());
    }
    {
        const o = date.getDay();
        try expect(o.isValid());
    }
    {
        const o = date.getHour();
        try expect(o.isValid());
    }
    {
        const o = date.getMinute();
        try expect(o.isValid());
    }
    {
        const o = date.getSecond();
        try expect(o.isValid());
    }
}

pub fn fuzzFormat(input: []const u8) !void {
    const seed: u64 = if (input.len >= 8)
        @bitCast(input[0..8].*)
    else blk: {
        var seed_buf: [8]u8 = undefined;
        @memcpy(seed_buf[0..input.len], input[0..]);
        break :blk @bitCast(seed_buf);
    };
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    const nullWriter = std.io.null_writer;

    const year = getYear(random);
    try year.format("", .{}, nullWriter);
    try year.format("any", .{}, nullWriter);

    const date = getDate(random);

    try date.format("", .{}, nullWriter);
    try date.format("any", .{}, nullWriter);

    if (!date.isValid()) return;

    try date.getYear().format("any", .{}, nullWriter);
    try date.getMonth().format("any", .{}, nullWriter);
    try date.getDayOfMonth().format("any", .{}, nullWriter);
    // try date.getDayOfYear().format("any", .{}, nullWriter);
    try date.getHour().format("any", .{}, nullWriter);
    try date.getMinute().format("any", .{}, nullWriter);
    try date.getSecond().format("any", .{}, nullWriter);
}

const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const Random = std.Random;
const DateTime = @import("DateTime.zig");
const Year = DateTime.Year;
