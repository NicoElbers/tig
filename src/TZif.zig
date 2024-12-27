header: TZifHeader,
data_block: TZifDataBlock,

/// In this parser we only distinguish between version 1 and 2+, as versions
/// 3 and 4 are strictly extensions to version 2.
const Version = enum {
    @"1",
    @"2+",

    pub fn parse(version_byte: u8) Version {
        return switch (version_byte) {
            0x00 => .@"1",
            0x32...0x34 => .@"2+",
            else => |v| blk: {
                // We assume version 4, as version 4 is the last extension we
                // implement
                log.warn("Unknown version: {d}, assuming version 4", .{v});
                break :blk .@"2+";
            },
        };
    }

    pub fn timeSize(version: Version) usize {
        return switch (version) {
            .@"1" => 4 * @sizeOf(u8),
            .@"2+" => 8 * @sizeOf(u8),
        };
    }
};
pub const TZifHeader = struct {
    version: Version,
    isutcnt: u32,
    isstdcnt: u32,
    leapcnt: u32,
    timecnt: u32,
    typecnt: u32,
    charcnt: u32,

    /// Parses TZif header. Assumes the next byte the reader reads is the first byte
    /// of the magic bytes
    fn parse(r: AnyReader) ?TZifHeader {
        // Verify magic
        {
            const magic = "TZif";
            var read_magic: [4]u8 = undefined;
            r.readNoEof(&read_magic) catch return null;
            if (!std.mem.eql(u8, magic, &read_magic)) return null;
        }

        const version = Version.parse(r.readByte() catch return null);

        // Unused bytes
        r.skipBytes(15, .{ .buf_size = 15 }) catch return null;

        // A four-octet unsigned integer specifying the number of UT/local indicators contained in
        // the data block -- MUST either be zero or equal to "typecnt".
        const isutcnt = blk: {
            var oct4: [4]u8 = undefined;
            r.readNoEof(&oct4) catch return null;
            break :blk mem.readInt(u32, &oct4, .big);
        };

        // A four-octet unsigned integer specifying the number of standard/wall indicators
        // contained in the data block -- MUST either be zero or equal to "typecnt".
        const isstdcnt = blk: {
            var oct4: [4]u8 = undefined;
            r.readNoEof(&oct4) catch return null;
            break :blk mem.readInt(u32, &oct4, .big);
        };

        // A four-octet unsigned integer specifying the number of leap-second records contained
        // in the data block.
        const leapcnt = blk: {
            var oct4: [4]u8 = undefined;
            r.readNoEof(&oct4) catch return null;
            break :blk mem.readInt(u32, &oct4, .big);
        };

        // A four-octet unsigned integer specifying the number of transition times contained in
        // the data block.
        const timecnt = blk: {
            var oct4: [4]u8 = undefined;
            r.readNoEof(&oct4) catch return null;
            break :blk mem.readInt(u32, &oct4, .big);
        };

        // A four-octet unsigned integer specifying the number of local time type records
        // contained in the data block -- MUST NOT be zero. (Although local time type records convey no
        // useful information in files that have non-empty TZ strings but no transitions, at least one such
        // record is nevertheless required because many TZif readers reject files that have zero time
        // types.)
        const typecnt = blk: {
            var oct4: [4]u8 = undefined;
            r.readNoEof(&oct4) catch return null;
            const n = mem.readInt(u32, &oct4, .big);

            break :blk n;
        };

        // A four-octet unsigned integer specifying the total number of octets used by the set of
        // time zone designations contained in the data block -- MUST NOT be zero. The count includes
        // the trailing NUL (0x00) octet at the end of the last time zone designation.
        const charcnt = blk: {
            var oct4: [4]u8 = undefined;
            r.readNoEof(&oct4) catch return null;
            break :blk mem.readInt(u32, &oct4, .big);
        };

        // Since we did not have the entire header before, we can only check isutcnt,
        // isstdcnt, typecnt and charcnt invariants now.
        if (isutcnt != 0 and isutcnt != typecnt) return null;
        if (isstdcnt != 0 and isstdcnt != typecnt) return null;
        if (typecnt == 0) log.warn("typecnt is 0, this is against RFC 9636", .{});
        if (charcnt == 0) return null;

        return .{
            .version = version,
            .isutcnt = isutcnt,
            .isstdcnt = isstdcnt,
            .leapcnt = leapcnt,
            .timecnt = timecnt,
            .typecnt = typecnt,
            .charcnt = charcnt,
        };
    }

    /// Data block:
    /// +---------------------------------------------------------+
    /// | transition times (timecnt x TIME_SIZE)                  |
    /// +---------------------------------------------------------+
    /// | transition types (timecnt)                              |
    /// +---------------------------------------------------------+
    /// | local time type records (typecnt x 6)                   |
    /// +---------------------------------------------------------+
    /// | time zone designations (charcnt)                        |
    /// +---------------------------------------------------------+
    /// | leap-second records (leapcnt x (TIME_SIZE + 4))         |
    /// +---------------------------------------------------------+
    /// | standard/wall indicators (isstdcnt)                     |
    /// +---------------------------------------------------------+
    /// | UT/local indicators (isutcnt)                           |
    /// +---------------------------------------------------------+
    ///
    pub fn dataBlockSize(header: TZifHeader) usize {
        const time_size = header.version.timeSize();

        var size: usize = 0;
        size += header.timecnt * time_size;
        size += header.timecnt;
        size += header.typecnt * 6;
        size += header.charcnt;
        size += header.leapcnt * (time_size + 4);
        size += header.isstdcnt;
        size += header.isutcnt;

        return size;
    }

    /// Skip the amount of bytes that this headers data block describes
    pub fn skipDataBlock(header: TZifHeader, r: AnyReader) void {
        const size = header.dataBlockSize();

        // Since we're skipping we don't really care if we hit EOF, thus we discard
        // this
        r.skipBytes(size, .{}) catch {};
    }
};

/// The data block representation assumes v2+, aka the time values are 64 bits,
/// however can parse both v1 and v2+
pub const TZifDataBlock = struct {
    transition_times: []const Transition,
    local_time_type_records: []const LocalTimeRecord,
    timezone_designation: [:0]const u8,
    leap_second_records: []const LeapSecondRecord,
    std_wall_indicators: ?[]const StdWallIndicator,
    ut_local_indicators: ?[]const UtLocalIndicator,

    pub const Error = error{
        InvalidDataBlock,
    } || Allocator.Error;

    pub const Transition = struct {
        unix_timestamp: i64,
        idx: u32,
    };

    pub const LocalTimeRecord = struct {
        offset: i32,
        designation_idx: u32,
        daylight_savings_time: bool,
    };

    pub const LeapSecondRecord = struct {
        occurrence: i64,
        correction: i32,
    };

    pub const StdWallIndicator = enum { standard, wall };
    pub const UtLocalIndicator = enum { universal, local };

    pub fn deinit(self: TZifDataBlock, alloc: Allocator) void {
        alloc.free(self.transition_times);
        alloc.free(self.local_time_type_records);
        alloc.free(self.timezone_designation);
        alloc.free(self.leap_second_records);

        if (self.std_wall_indicators) |swi| {
            alloc.free(swi);
        }

        if (self.ut_local_indicators) |utl| {
            alloc.free(utl);
        }
    }

    pub fn parse(alloc: Allocator, r: AnyReader, header: TZifHeader) Error!TZifDataBlock {
        const time_size = header.version.timeSize();
        assert(time_size == 4 or time_size == 8);

        const transition_times = blk: {
            var transition_times = try alloc.alloc(Transition, header.timecnt);
            errdefer alloc.free(transition_times);

            // Parse transition times
            for (0..header.timecnt) |i| {
                const timestamp: i64 = switch (time_size) {
                    4 => @as(i64, r.readInt(i32, .big) catch return Error.InvalidDataBlock),
                    8 => r.readInt(i64, .big) catch return Error.InvalidDataBlock,
                    else => return Error.InvalidDataBlock,
                };

                if (timestamp < -(comptime std.math.powi(i64, 2, 59) catch unreachable))
                    log.warn("Transition timestamp < -2^59, this is against RFC 9636", .{});

                transition_times[i].unix_timestamp = timestamp;
            }

            // Parse transition types
            for (0..header.timecnt) |i| {
                const idx: u8 = r.readInt(u8, .big) catch return Error.InvalidDataBlock;

                if (idx >= header.typecnt)
                    return Error.InvalidDataBlock;

                transition_times[i].idx = idx;
            }

            break :blk transition_times;
        };
        errdefer alloc.free(transition_times);

        const local_time_type_records = blk: {
            var local_time_type_records = try alloc.alloc(LocalTimeRecord, header.typecnt);
            errdefer alloc.free(local_time_type_records);

            // Parse local time type records
            for (0..header.typecnt) |i| {
                const offset = r.readInt(i32, .big) catch return Error.InvalidDataBlock;

                if (offset == std.math.minInt(i32))
                    log.warn("Local time record offset is -2^59, this is against RFC 9636", .{});

                if (93_599 < offset or offset < -89_999)
                    log.warn("Local time record offset 26 < offset < -25, this is against RFC 9636", .{});

                const daylight_saving_time = dst: {
                    const byte = r.readInt(u8, .big) catch return Error.InvalidDataBlock;

                    break :dst switch (byte) {
                        0 => false,
                        1 => true,
                        else => return Error.InvalidDataBlock,
                    };
                };

                const designation_idx = r.readInt(u8, .big) catch return Error.InvalidDataBlock;

                if (designation_idx >= header.charcnt) return Error.InvalidDataBlock;

                local_time_type_records[i] = .{
                    .offset = offset,
                    .designation_idx = designation_idx,
                    .daylight_savings_time = daylight_saving_time,
                };
            }

            break :blk local_time_type_records;
        };
        errdefer alloc.free(local_time_type_records);

        const timezone_designation: [:0]const u8 = blk: {
            assert(header.charcnt > 0);

            const full_str = try alloc.alloc(u8, header.charcnt);
            errdefer alloc.free(full_str);

            // Parse Time zone designations
            r.readNoEof(full_str) catch return Error.InvalidDataBlock;

            // Must be a null terminated string
            if (full_str[header.charcnt - 1] != 0)
                return Error.InvalidDataBlock;

            break :blk full_str[0 .. header.charcnt - 1 :0];
        };
        errdefer alloc.free(timezone_designation);

        const leap_second_records = blk: {
            var leap_second_records = try alloc.alloc(LeapSecondRecord, header.leapcnt);
            errdefer alloc.free(leap_second_records);

            // Parse leap second records
            for (0..header.leapcnt) |i| {
                const occurrence = switch (time_size) {
                    4 => @as(i64, r.readInt(i32, .big) catch return Error.InvalidDataBlock),
                    8 => r.readInt(i64, .big) catch return Error.InvalidDataBlock,
                    else => return Error.InvalidDataBlock,
                };

                const correction = r.readInt(i32, .big) catch return Error.InvalidDataBlock;

                leap_second_records[i] = .{
                    .occurrence = occurrence,
                    .correction = correction,
                };
            }

            break :blk leap_second_records;
        };
        errdefer alloc.free(leap_second_records);

        const std_wall_indicators: ?[]const StdWallIndicator = blk: {
            if (header.isstdcnt == 0) break :blk null;

            var std_wall_indicators = try alloc.alloc(StdWallIndicator, header.isstdcnt);
            errdefer alloc.free(std_wall_indicators);

            // Parse standard/wall indicators
            for (0..header.isstdcnt) |i| {
                const byte = r.readInt(u8, .big) catch return Error.InvalidDataBlock;

                const indicator: StdWallIndicator = switch (byte) {
                    0 => .wall,
                    1 => .standard,
                    else => return Error.InvalidDataBlock,
                };

                std_wall_indicators[i] = indicator;
            }

            break :blk std_wall_indicators;
        };
        errdefer if (std_wall_indicators) |swi| alloc.free(swi);

        const ut_local_indicators: ?[]const UtLocalIndicator = blk: {
            if (header.isutcnt == 0) break :blk null;

            var ut_local_indicators = try alloc.alloc(UtLocalIndicator, header.isutcnt);
            errdefer alloc.free(ut_local_indicators);

            // Parse UT/local indicators
            for (0..header.isutcnt) |i| {
                const byte = r.readInt(u8, .big) catch return Error.InvalidDataBlock;

                const indicator: UtLocalIndicator = switch (byte) {
                    0 => .local,
                    1 => .universal,
                    else => return Error.InvalidDataBlock,
                };

                if (std_wall_indicators) |swi| {
                    assert(i < swi.len);

                    if (indicator == .universal and swi[i] != .standard)
                        return Error.InvalidDataBlock;
                }

                ut_local_indicators[i] = indicator;
            }

            break :blk ut_local_indicators;
        };
        errdefer if (ut_local_indicators) |utl| alloc.free(utl);

        return .{
            .transition_times = transition_times,
            .local_time_type_records = local_time_type_records,
            .timezone_designation = timezone_designation,
            .leap_second_records = leap_second_records,
            .std_wall_indicators = std_wall_indicators,
            .ut_local_indicators = ut_local_indicators,
        };
    }
};

const potential_paths = [_][]const u8{
    "/etc/localtime",
};

pub fn deinit(self: TZif, alloc: Allocator) void {
    self.data_block.deinit(alloc);
}

/// Do a best attempt at finding the systems time zone information file.
/// If at some point we cannot open a file we expect may have a tzif, silently
/// fail.
pub fn findTzif(alloc: Allocator) !?TZif {
    switch (@import("builtin").os.tag) {
        .windows => return null,
        else => {},
    }

    for (potential_paths) |path| {
        const file = fs.openFileAbsolute(path, .{}) catch continue;

        const tzif = parseTzif(alloc, file.reader().any());

        if (tzif != null) return tzif;
    }

    return null;
}

/// A tzif parser based on RFC 9636, modified slightly to be more permissive
/// to bad input. Any out of spec modifications will result in a logged warning.
pub fn parseTzif(alloc: Allocator, r: AnyReader) ?TZif {
    const header = blk: {
        var h1 = TZifHeader.parse(r) orelse return null;

        // We have a v1 header, we need to actually use it
        if (h1.version == .@"1") break :blk h1;

        assert(h1.version == .@"2+");

        // We have a v2+ header, we can skip the v1 header and
        // The first header, which is for the v1 data block, still says the
        // version is v2. So we manually override it.
        h1.version = .@"1";
        h1.skipDataBlock(r);

        const h2 = TZifHeader.parse(r) orelse return null;

        // TODO: Handle this case?
        if (h2.version != .@"2+") unreachable;

        break :blk h2;
    };

    const data_block = TZifDataBlock.parse(alloc, r, header) catch return null;

    return .{
        .header = header,
        .data_block = data_block,
    };
}

const std = @import("std");
const fs = std.fs;
const fmt = std.fmt;
const mem = std.mem;

const File = fs.File;
const AnyReader = std.io.AnyReader;
const OpenError = std.posix.OpenError;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.tzif);
const assert = std.debug.assert;

const TZif = @This();
