fn logFuzz(comptime fmt: []const u8, args: anytype) void {
    if (!@import("builtin").fuzz) return;

    _ = fmt;
    _ = args;
    // std.debug.print(fmt ++ "\n", args);
}

fn getDate(r: Random) DateTime {
    // 50/50 valid/invalid
    const timestamp = switch (r.int(u2)) {
        0 => r.intRangeAtMostBiased(i64, DateTime.date_max.timestamp, std.math.maxInt(i64)),
        1 => r.intRangeAtMostBiased(i64, std.math.minInt(i64), DateTime.date_min.timestamp),
        else => getValidDate(r).timestamp,
    };

    const date: DateTime = .{ .timestamp = timestamp };

    logFuzz("Date: {d}", .{date});
    return date;
}

fn getValidDate(r: Random) DateTime {
    const date = DateTime.fromGregorianTimestamp(r.intRangeAtMostBiased(
        i64,
        DateTime.date_min.timestamp,
        DateTime.date_max.timestamp,
    ));
    logFuzz("Date: {d}", .{date});
    return date;
}

fn getYear(r: Random) Year {
    const year: Year = @enumFromInt(r.int(i64));
    logFuzz("Year: {d}", .{year});
    return year;
}

fn getValidYear(r: Random) Year {
    const year = Year.from(r.intRangeAtMostBiased(i40, Year.min.to(), Year.max.to()));
    logFuzz("Year: {d}", .{year});
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

    const date = getValidDate(random);

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

    const date = getValidDate(random);

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

    try expect(date.getYear().isValid());
    try expect(date.getDayOfYear().isValid(date.getYear().isLeapYear()));
    _ = date.getMonth();
    try expect(date.getDayOfMonth().isValid(date.getMonth(), date.getYear().isLeapYear()));
    try expect(date.getWeekOfYear().isValid(date.getYear()));
    _ = date.getDayOfWeek();
    try expect(date.getWeek().isValid());
    try expect(date.getDay().isValid());
    try expect(date.getHour().isValid());
    try expect(date.getMinute().isValid());
    try expect(date.getSecond().isValid());
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
    try year.format("a", .{}, nullWriter);

    const date = getDate(random);

    try date.format("", .{}, nullWriter);
    try date.format("a", .{}, nullWriter);

    if (!date.isValid()) return;

    try date.getYear().format("", .{}, nullWriter);
    try date.getYear().format("a", .{}, nullWriter);

    try date.getMonth().format("", .{}, nullWriter);
    try date.getMonth().format("a", .{}, nullWriter);

    try date.getDayOfMonth().format("", .{}, nullWriter);
    try date.getDayOfMonth().format("a", .{}, nullWriter);

    try date.getDayOfYear().format("", .{}, nullWriter);
    try date.getDayOfYear().format("a", .{}, nullWriter);

    try date.getHour().format("", .{}, nullWriter);
    try date.getHour().format("a", .{}, nullWriter);

    try date.getMinute().format("", .{}, nullWriter);
    try date.getMinute().format("a", .{}, nullWriter);

    try date.getSecond().format("", .{}, nullWriter);
    try date.getSecond().format("a", .{}, nullWriter);
}

pub fn fuzzValidate(input: []const u8) !void {
    const seed: u64 = if (input.len >= 8)
        @bitCast(input[0..8].*)
    else blk: {
        var seed_buf: [8]u8 = undefined;
        @memcpy(seed_buf[0..input.len], input[0..]);
        break :blk @bitCast(seed_buf);
    };
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    { // valid_date.isValid works on any date
        const date = getDate(random);
        _ = date.isValid();
    }

    // All the getters assume a valid date
    const date = getValidDate(random);

    _ = date.getYear().isValid();
    _ = date.getDayOfYear().isValid(date.getYear().isLeapYear());
    _ = date.getWeekOfYear().isValid(date.getYear());
    _ = date.getWeek().isValid();
    _ = date.getDay().isValid();
    _ = date.getHour().isValid();
    _ = date.getMinute().isValid();
    _ = date.getSecond().isValid();
}

const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const Random = std.Random;
const DateTime = @import("DateTime.zig");
const Year = DateTime.Year;
const Week = DateTime.Week;
