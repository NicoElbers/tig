header: TZifHeader,
data_block: TZifDataBlock,
footer: ?TZifFooter,

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

    pub const Error = Reader.Error || error{InvalidHeader};

    /// Parses TZif header. Assumes the next byte the reader reads is the first byte
    /// of the magic bytes
    fn parse(r: *Reader) Error!TZifHeader {
        // Verify magic
        {
            const magic = "TZif";
            if (!std.mem.eql(u8, magic, try r.take(magic.len))) return error.InvalidHeader;
        }

        const version = Version.parse(try r.takeByte());

        // 15 Unused bytes
        try r.discardAll(15);

        // A four-octet unsigned integer specifying the number of UT/local indicators contained in
        // the data block -- MUST either be zero or equal to "typecnt".
        const isutcnt = try r.takeInt(u32, .big);

        // A four-octet unsigned integer specifying the number of standard/wall indicators
        // contained in the data block -- MUST either be zero or equal to "typecnt".
        const isstdcnt = try r.takeInt(u32, .big);

        // A four-octet unsigned integer specifying the number of leap-second records contained
        // in the data block.
        const leapcnt = try r.takeInt(u32, .big);

        // A four-octet unsigned integer specifying the number of transition times contained in
        // the data block.
        const timecnt = try r.takeInt(u32, .big);

        // A four-octet unsigned integer specifying the number of local time type records
        // contained in the data block -- MUST NOT be zero. (Although local time type records convey no
        // useful information in files that have non-empty TZ strings but no transitions, at least one such
        // record is nevertheless required because many TZif readers reject files that have zero time
        // types.)
        const typecnt = try r.takeInt(u32, .big);

        // A four-octet unsigned integer specifying the total number of octets used by the set of
        // time zone designations contained in the data block -- MUST NOT be zero. The count includes
        // the trailing NUL (0x00) octet at the end of the last time zone designation.
        const charcnt = try r.takeInt(u32, .big);

        // Since we did not have the entire header before, we can only check isutcnt,
        // isstdcnt, typecnt and charcnt invariants now.
        if (isutcnt != 0 and isutcnt != typecnt) return error.InvalidHeader;
        if (isstdcnt != 0 and isstdcnt != typecnt) return error.InvalidHeader;
        if (typecnt == 0) log.warn("typecnt is 0, this is against RFC 9636", .{});
        if (charcnt == 0) return error.InvalidHeader;

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
    pub fn skipDataBlock(header: TZifHeader, r: *Reader) error{ReadFailed}!void {
        const size = header.dataBlockSize();

        r.discardAll(size) catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            // Since we're skipping we don't really care if we hit EOF, thus we
            // discard this
            error.EndOfStream => {},
        };
    }
};

/// The data block representation assumes v2+, aka the time values are 64 bits,
/// however can parse both v1 and v2+
pub const TZifDataBlock = struct {
    transition_times: []const Transition,
    local_time_type_records: []const LocalTimeRecord,
    timezone_designation: []const u8,

    /// Leap second records
    ///
    /// If these records have an expiration date (as per version 4), this should
    /// NOT be included in this field. It should be included in `leap_second_expiration`
    leap_second_records: []const LeapSecondRecord,
    leap_second_expiration: ?i64,

    // TODO: Consolidate these two into a single array
    // this is kinda wasteful and hard to parse
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

    // TODO: fix error set
    pub fn parse(alloc: Allocator, header: TZifHeader, r: *Reader) !TZifDataBlock {
        // We know the exact size, so ensure we also consume the exact size
        const seek_before = r.seek;

        const time_size = header.version.timeSize();
        assert(time_size == 4 or time_size == 8);

        const transition_times = blk: {
            var transition_times = try alloc.alloc(Transition, header.timecnt);
            errdefer alloc.free(transition_times);

            // Parse transition times
            for (0..header.timecnt) |i| {
                const timestamp: i64 = switch (time_size) {
                    4 => try r.takeInt(i32, .big),
                    8 => try r.takeInt(i64, .big),
                    else => unreachable,
                };

                if (timestamp < -(comptime std.math.powi(i64, 2, 59) catch unreachable))
                    log.warn("Transition timestamp < -2^59, this is against RFC 9636", .{});

                transition_times[i].unix_timestamp = timestamp;
            }

            // Parse transition types
            for (0..header.timecnt) |i| {
                const idx: u8 = try r.takeByte();

                if (idx >= header.typecnt)
                    return error.InvalidDataBlock;

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
                const offset = try r.takeInt(i32, .big);

                if (offset == std.math.minInt(i32))
                    log.warn("Local time record offset is -2^59, this is against RFC 9636", .{});

                if (93_599 < offset or offset < -89_999)
                    log.warn("Local time record offset 26 < offset < -25, this is against RFC 9636", .{});

                const daylight_saving_time = dst: {
                    const byte = try r.takeByte();

                    break :dst switch (byte) {
                        0 => false,
                        1 => true,
                        else => return error.InvalidDataBlock,
                    };
                };

                const designation_idx = try r.takeByte();

                if (designation_idx >= header.charcnt) return error.InvalidDataBlock;

                local_time_type_records[i] = .{
                    .offset = offset,
                    .designation_idx = designation_idx,
                    .daylight_savings_time = daylight_saving_time,
                };
            }

            break :blk local_time_type_records;
        };
        errdefer alloc.free(local_time_type_records);

        const timezone_designation: []const u8 = blk: {
            assert(header.charcnt > 0);

            // Parse Time zone designations
            const timezone_designation = try r.readAlloc(alloc, header.charcnt);
            errdefer alloc.free(timezone_designation);

            // Must be a null terminated string
            if (timezone_designation[header.charcnt - 1] != 0)
                return Error.InvalidDataBlock;

            break :blk timezone_designation;
        };
        errdefer alloc.free(timezone_designation);

        const leap_second_records, const leap_second_expiration = blk: {
            var leap_second_records = try alloc.alloc(LeapSecondRecord, header.leapcnt);
            errdefer alloc.free(leap_second_records);

            // Parse leap second records
            for (0..header.leapcnt) |i| {
                const occurrence: i64 = switch (time_size) {
                    4 => try r.takeInt(i32, .big),
                    8 => try r.takeInt(i64, .big),
                    else => unreachable,
                };

                const correction = try r.takeInt(i32, .big);

                leap_second_records[i] = .{
                    .occurrence = occurrence,
                    .correction = correction,
                };
            }

            // the correction value of the last two records MAY be the same, with
            // the occurrence of last record indicating the expiration time of the
            // leap-second table.
            if (header.leapcnt < 2) break :blk .{ leap_second_records, null };

            const last_rec = leap_second_records[header.leapcnt - 1];
            const second_last_rec = leap_second_records[header.leapcnt - 2];

            if (last_rec.correction != second_last_rec.correction)
                break :blk .{ leap_second_records, null };

            break :blk .{
                leap_second_records[0 .. leap_second_records.len - 1], // list
                leap_second_records[leap_second_records.len - 1].occurrence, // expiry
            };
        };
        errdefer alloc.free(leap_second_records);

        const std_wall_indicators: ?[]const StdWallIndicator = blk: {
            if (header.isstdcnt == 0) break :blk null;

            var std_wall_indicators = try alloc.alloc(StdWallIndicator, header.isstdcnt);
            errdefer alloc.free(std_wall_indicators);

            // Parse standard/wall indicators
            for (0..header.isstdcnt) |i| {
                const byte = try r.takeByte();

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
                const byte = try r.takeByte();

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

        assert(r.seek == seek_before + header.dataBlockSize());
        return .{
            .transition_times = transition_times,
            .local_time_type_records = local_time_type_records,
            .timezone_designation = timezone_designation,
            .leap_second_records = leap_second_records,
            .leap_second_expiration = leap_second_expiration,
            .std_wall_indicators = std_wall_indicators,
            .ut_local_indicators = ut_local_indicators,
        };
    }
};

pub const TZifFooter = struct {
    tz_string: TZString,

    pub const Error = error{
        InvalidFooter,
    } || Allocator.Error || TZString.Error;

    pub fn deinit(self: TZifFooter, alloc: Allocator) void {
        self.tz_string.deinit(alloc);
    }

    pub const ParseFooterError = Allocator.Error || error{ ReadFailed, InvalidFooter };
    pub fn parse(alloc: Allocator, r: *Reader) ParseFooterError!TZifFooter {
        {
            const byte = r.takeByte() catch |err| switch (err) {
                error.ReadFailed => return error.ReadFailed,
                error.EndOfStream => return error.InvalidFooter,
            };
            if (byte != '\n') return Error.InvalidFooter;
        }

        const tz_string = TZString.parse(alloc, r) catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidTzString => return error.InvalidFooter,
        };

        if ('\n' != r.takeByte() catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.EndOfStream => 0,
        }) return error.InvalidFooter;

        return .{ .tz_string = tz_string };
    }
};

const potential_tzif_paths = [_][:0]const u8{
    "/etc/localtime",
    "/etc/timezone",
};

pub fn deinit(self: TZif, alloc: Allocator) void {
    self.data_block.deinit(alloc);
    if (self.footer) |f| {
        f.deinit(alloc);
    }
}

/// Do a best attempt at finding the systems time zone information file.
const FindError = Allocator.Error || Io.Cancelable || Io.UnexpectedError;
pub fn findTzif(alloc: Allocator, io: Io) FindError!?TZif {
    switch (@import("builtin").os.tag) {
        .windows => return null,
        else => {},
    }

    // Try hardcoded paths
    for (potential_tzif_paths) |path| {
        const file = File.openAbsolute(io, path, .{}) catch |err| switch (err) {
            error.Canceled => return error.Canceled,

            error.SystemResources,
            error.ProcessFdQuotaExceeded,
            error.SystemFdQuotaExceeded,
            => return error.OutOfMemory,

            error.NameTooLong,
            error.BadPathName,
            error.FileNotFound,
            error.NoDevice,
            error.NetworkNotFound,
            error.ProcessNotFound,
            error.IsDir,
            error.AccessDenied,
            error.PermissionDenied,
            error.SymLinkLoop,
            error.FileTooBig,
            error.SharingViolation,
            error.PipeBusy,
            error.AntivirusInterference,
            error.DeviceBusy,
            => continue,

            error.NoSpaceLeft,
            error.FileLocksNotSupported,
            error.NotDir,
            error.FileBusy,
            error.PathAlreadyExists,
            error.WouldBlock,
            error.Unexpected,
            => return error.Unexpected,
        };
        defer file.close(io);

        var read_buf: [4096]u8 = undefined;
        var file_reader = file.reader(io, &read_buf);

        // Ignore any invalid tzif files
        const tzif = parseTzif2(alloc, &file_reader.interface) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };

        return tzif;
    }

    return null;
}

pub const ParseError = TZifHeader.Error || TZifDataBlock.Error || TZifFooter.Error;

/// A tzif parser based on RFC 9636, modified slightly to be more permissive
/// to bad input. Any out of spec modifications will result in a logged warning.
pub fn parseTzif2(alloc: Allocator, r: *Reader) ParseError!TZif {
    assert(r.buffer.len >= 44);

    const header = blk: {
        var h1 = try TZifHeader.parse(r);

        // We have a v1 header, we need to actually use it
        if (h1.version == .@"1") break :blk h1;

        assert(h1.version == .@"2+");

        // We have a v2+ header, we can skip the v1 header and
        // The first header, which is for the v1 data block, still says the
        // version is v2. So we manually override it.
        h1.version = .@"1";
        try h1.skipDataBlock(r);

        // At this point we saw a valid first header, so we can assume this is
        // a TZif file
        var h2 = try TZifHeader.parse(r);

        if (h2.version != .@"2+") {
            log.warn("Second header does not indicate v2+, this is against RFC 9636", .{});
            h2.version = .@"2+";
        }

        break :blk h2;
    };

    const data_block = try TZifDataBlock.parse(alloc, header, r);
    errdefer data_block.deinit(alloc);

    if (header.version == .@"1") {
        const parsed: TZif = .{
            .header = header,
            .data_block = data_block,
            .footer = null,
        };

        // Final sanity check
        assert(parsed.isValid());

        return parsed;
    }

    const footer = try TZifFooter.parse(alloc, r);

    const parsed: TZif = .{
        .header = header,
        .data_block = data_block,
        .footer = footer,
    };

    // Final sanity check
    assert(parsed.isValid());
    return parsed;
}

pub fn isValid(tzif: TZif) bool {
    const header = tzif.header;
    const data = tzif.data_block;

    // isutcnt
    // A four-octet unsigned integer specifying the number of UT/local indicators
    // contained in the data block -- MUST either be zero or equal to "typecnt".
    if (header.isutcnt != 0 and
        (header.isutcnt != header.typecnt or
            data.ut_local_indicators == null or
            header.isutcnt != data.ut_local_indicators.?.len)) return false;

    // isstdcnt
    // A four-octet unsigned integer specifying the number of standard/wall indicators
    // contained in the data block -- MUST either be zero or equal to "typecnt".
    if (header.isstdcnt != 0 and
        (header.isstdcnt != header.typecnt or
            data.std_wall_indicators == null or
            header.isstdcnt != data.std_wall_indicators.?.len)) return false;

    // leapcnt
    // A four-octet unsigned integer specifying the number of leap-second records
    // contained in the data block.
    const leap_second_record_count = data.leap_second_records.len + @intFromBool(data.leap_second_expiration != null);
    if (header.leapcnt != leap_second_record_count) return false;

    // timecnt
    // A four-octet unsigned integer specifying the number of transition times
    // contained in the data block.
    if (header.timecnt != data.transition_times.len) return false;

    // typecnt
    // A four-octet unsigned integer specifying the number of local time type records
    // contained in the data block -- MUST NOT be zero. (Although local time type records
    // convey no useful information in files that have non-empty TZ strings but
    // no transitions, at least one such record is nevertheless required because
    // many TZif readers reject files that have zero time types.)
    //
    // NOTE: zero check omited to be more permissive to bad data,
    // warning generated while parsing
    if (header.typecnt != data.local_time_type_records.len) return false;

    // charcnt
    // A four-octet unsigned integer specifying the total number of octets used by the set of
    // time zone designations contained in the data block -- MUST NOT be zero. The count includes
    // the trailing NUL (0x00) octet at the end of the last time zone designation.
    if (header.charcnt == 0 or header.charcnt != data.timezone_designation.len) return false;

    // transition times
    // A series of four- or eight-octet UNIX leap time values sorted in strictly
    // ascending order. Each value is used as a transition time at which the rules
    // for computing local time may change. The number of time values is specified
    // by the "timecnt" field in the header.
    //
    // Each time value be at least -2^59. (-2^59 is the greatest negated power of
    // 2 that predates the Big Bang, and avoiding earlier timestamps works around
    // known TZif reader bugs relating to outlandishly negative timestamps.)
    //
    // NOTE: -2^59 check omited, warning generated while parsing
    //
    // transition types
    // A series of one-octet unsigned integers specifying the type of local time
    // of the corresponding transition time. These values serve as zero-based
    // indices into the array of local time type records. The number of type indices
    // is specified by the "timecnt" field in the header. Each type index be
    // in the range [0, "typecnt" - 1].
    var prev_trans_time: i64 = std.math.minInt(i64);
    for (data.transition_times) |trans| {
        // Transition time check
        if (prev_trans_time >= trans.unix_timestamp) return false;
        prev_trans_time = trans.unix_timestamp;

        // Transion type check
        if (trans.idx >= header.typecnt) return false;
    }

    // local time type records
    // A series of six-octet records specifying a local time type. The number of
    // records is specified by the "typecnt" field in the header. Each record has
    // the following format (the lengths of multi-octet fields are shown in parentheses):
    //
    // ```
    //  +---------------+---+---+
    //  | utoff (4)     |dst|idx|
    //  +---------------+---+---+
    // ```
    //
    // utoff
    // A four-octet signed integer specifying the number of seconds to be added
    // to UT in order to determine local time. The value MUST NOT be -2^31 and
    // SHOULD be in the range [-89999, 93599] (i.e., its value be more than -25
    // hours and less than 26 hours).
    //
    // Avoiding -2^31 allows 32-bit clients to negate the value without overflow.
    // Restricting it to [-89999, 93599] allows easy support by implementations
    // that already support the POSIX- required range [-24:59:59, 25:59:59].
    //
    // NOTE: Both the -2^31 and the [-89999, 93599] checks are omited,
    // warnings are generated while parsing for both
    //
    // (is)dst
    // A one-octet value indicating whether local time should be considered
    // Daylight Saving Time (DST). The value MUST be 0 or 1. A value of one (1)
    // indicates that this type of time is DST. A value of zero (0) indicates
    // that this time type is standard time.
    //
    // NOTE: As this is already represented as a bool, this cannot be invalid
    //
    // (desig)idx:
    // A one-octet unsigned integer specifying a zero-based index into the series
    // of time zone designation octets, thereby selecting a particular designation
    // string. Each index be in the range [0, "charcnt" - 1]; it designates the
    // NUL‑terminated string of octets starting at position "idx" in the
    // time zone designations. (This string MAY be empty.) A NUL octet MUST exist
    // in the time zone designations at or after position "idx". If the designation
    // string is "-00", the time type is a placeholder indicating that
    // local time is unspecified.
    for (data.local_time_type_records) |rec| {
        if (rec.designation_idx >= header.charcnt) return false;
    }

    // time zone designations
    // A series of octets constituting an array of NUL‑terminated (0x00) time
    // zone designation strings. The total number of octets is specified by the
    // "charcnt" field in the header. Two designations overlap if one is a suffix
    // of the other. The character encoding of time zone designation strings is
    // not specified; however, see Section 4 of this document.
    if (data.timezone_designation[data.timezone_designation.len - 1] != 0) return false;

    // leap second records
    // A series of eight- or twelve-octet records specifying the corrections that
    // need to be applied to UTC in order to determine TAI, also known as the
    // leap-second table. The records are sorted by the occurrence time in strictly
    // ascending order. The number of records is specified by the "leapcnt" field
    // in the header. Each record has one of the following structures
    // (the lengths of multi-octet fields are shown in parentheses):
    //
    // Version 1 Data Block:
    // ```
    // +---------------+---------------+
    // | occur (4)     | corr (4)      |
    // +---------------+---------------+
    // ```
    //
    // Version 2+ Data Block:
    // ```
    // +---------------+---------------+---------------+
    // | occur (8)                     | corr (4)      |
    // +---------------+---------------+---------------+
    // ```
    //
    // occur(ence):
    // A four- or eight-octet UNIX leap time value specifying the time at which
    // a leap-second correction occurs or at which the leap-second table expires.
    // The first value, if present, MUST be non-negative, and each leap second
    // MUST occur at the end of a UTC month.
    //
    // TODO: See if I want to verify end of UTC month, or be more permissive and
    // extend it to the end of a minute, or allow any second (although how do
    // we represent that?)
    //
    // corr(ection):
    // A four-octet signed integer specifying the value of LEAPCORR on or after
    // the occurrence. If "leapcnt" is zero, LEAPCORR is zero for all timestamps.
    // If "leapcnt" is nonzero, for timestamps before the first occurrence time,
    // LEAPCORR is zero if the first correction is one (1) or minus one (-1) and
    // is unspecified otherwise (which can happen only in files truncated at the
    // start (Section 6.1)).
    //
    // The first leap second is a positive leap second if and only if its
    // correction is positive. Each correction after the first MUST differ from
    // the previous correction by either one (1) for a positive leap second or
    // minus one (-1) for a negative leap second, except that in version 4 files
    // with two or more leap-second records, the correction value of the last two
    // records MAY be the same, with the occurrence of last record indicating the
    // expiration time of the leap-second table.
    //
    // The leap-second table expiration time is the time at which the table no
    // longer records the presence or absence of future leap-second corrections,
    // and post-expiration timestamps cannot be accurately calculated. For example,
    // a leap-second table published in January, which predicts the presence or
    // absence of a leap second at June's end, might expire in mid-December because
    // it is not known when the next leap second will occur.
    //
    // If leap seconds become permanently discontinued, as requested by the
    // General Conference on Weights and Measures, leap-second tables published
    // after the discontinuation time SHOULD NOT expire, since they will not be
    // updated in the foreseeable future.
    //
    // NOTE: since the expiration date is ?i64, we cannot further verify it
    var prev_occurence: i64 = -1;
    var prev_correction: i32 = 0;
    for (data.leap_second_records) |rec| {
        if (prev_occurence >= rec.occurrence) return false;
        prev_occurence = rec.occurrence;

        if (@abs(prev_correction - rec.correction) != 1) return false;
        prev_correction = rec.correction;
    }

    // We cannot have an expiration date with < 2 entries
    if (header.leapcnt < 2 and data.leap_second_expiration != null) return false;

    // standard/wall indicators
    // A series of one-octet values indicating whether the transition times
    // associated with local time types were specified as standard time or
    // wall-clock time. Each value MUST be 0 or 1. A value of one (1) indicates
    // standard time. The value MUST be set to one (1) if the corresponding UT/local
    // indicator is set to one (1). A value of zero (0) indicates wall time.
    // The number of values is specified by the "isstdcnt" field in the header.
    // If "isstdcnt" is zero (0), all transition times associated with local time
    // types are assumed to be specified as wall time.
    //
    // NOTE: as this is represented as a non exhaustive enum thus cannot be
    // invalid in that way
    //
    // UT/local indicators
    // A series of one-octet values indicating whether the transition times
    // associated with local time types were specified as UT or local time.
    // Each value MUST be 0 or 1. A value of one (1) indicates UT, and the
    // corresponding standard/wall indicator MUST also be set to one (1). A
    // value of zero (0) indicates local time. The number of values is specified
    // by the "isutcnt" field in the header. If "isutcnt" is zero (0), all
    // transition times associated with local time types are assumed to be
    // specified as local time.
    //
    // NOTE: as this is represented as a non exhaustive enum thus cannot be
    // invalid in that way

    if (data.std_wall_indicators) |swi| {
        if (data.ut_local_indicators) |utl| {
            for (swi, utl) |s, u| {
                if (u == .universal)
                    if (s != .standard) return false;
            }
        }
    } else {
        // All std/wall == .wall
        if (data.ut_local_indicators) |utl| {
            for (utl) |u| {
                if (u == .universal) return false;
            }
        }
    }

    if (header.version == .@"1") return true;

    if (tzif.footer == null) return false;

    // TODO: Add a footer.isValid() check

    return true;
}

const std = @import("std");
const fs = std.fs;
const fmt = std.fmt;
const mem = std.mem;

const Io = std.Io;
const Reader = Io.Reader;
const Writer = Io.Writer;
const File = Io.File;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.tzif);
const assert = std.debug.assert;

const TZif = @This();
const TZString = @import("TZString.zig");
