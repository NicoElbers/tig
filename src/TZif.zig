header: TZifHeader,

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






const potential_paths = [_][]const u8{
    "/etc/localtime",
};

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

    return .{
        .header = header,
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
