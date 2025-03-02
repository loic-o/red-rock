const std = @import("std");

pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn format(
        self: Date,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{}-{:0>2}-{:0>2}", .{ self.year, self.month, self.day });
    }
};

pub fn parse_date(buf: []const u8) !Date {
    if (buf.len != 10) return error.InvalidLength;
    return Date{
        .year = try std.fmt.parseInt(u16, buf[0..4], 10),
        .month = try std.fmt.parseInt(u8, buf[5..7], 10),
        .day = try std.fmt.parseInt(u8, buf[8..10], 10),
    };
}
