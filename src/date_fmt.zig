pub const FormatIntOptions = struct { filler: u8 = '0', min_length: ?usize = null };

/// duplicate of std.fmt.formatInt, however with hardcoded values and
/// importantly no '+' when a year is positive
pub fn formatInt(int_value: anytype, comptime opts: FormatIntOptions, writer: anytype) !void {
    @disableInstrumentation();

    const value_info = @typeInfo(@TypeOf(int_value)).int;

    // The type must have the same size as `base` or be wider in order for the
    // division to work
    const min_int_bits = comptime @max(value_info.bits, 8);
    const MinInt = std.meta.Int(.unsigned, min_int_bits);

    const abs_value = @abs(int_value);

    // The worst case in terms of space needed is base 2, plus 1 for the sign
    const minlen = if (opts.min_length) |min| min + 1 else 1;
    var buf: [1 + @as(comptime_int, @max(value_info.bits, minlen))]u8 = undefined;

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

    if (opts.min_length) |min| {
        while (index > buf.len - min) {
            index -= 1;
            buf[index] = opts.filler;
        }
    }

    if (int_value < 0) {
        // Negative integer
        index -= 1;
        buf[index] = '-';
    }

    try writer.writeAll(buf[index..]);
}

const std = @import("std");
