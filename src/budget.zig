const std = @import("std");

// for potential future ref: https://github.com/ziglibs/s2s/blob/master/s2s.zig
// de/serialization libaray for zig structs

pub const VTable = struct {
    test_fn: *const fn (ctx: *anyopaque) ?bool,
};

pub const Connection = struct {
    const Self = @This();

    ptr: *anyopaque,
    vtable: *const VTable,

    pub fn test_something(self: *Self) !bool {
        if (self.vtabel.test_fn(self.ptr)) |val| {
            return val;
        }
        return error.DidntWork;
    }
};

pub fn connect() Connection {
    unreachable;
}

pub fn dump(allocator: std.mem.Allocator, data_dir: []const u8) !void {
    var d = try std.fs.openDirAbsolute(data_dir, .{});
    defer d.close();

    const raw_data = try d.readFileAlloc(allocator, "2024-01-01 thru 2024-12-05 transactions.csv", 1024 * 1024);
    defer allocator.free(raw_data);

    var it = CsvTransactionIterator{ .buffer = raw_data };
    var cnt: usize = 0;
    while (it.next()) |tx| {
        std.debug.print("{}\n", .{tx});
        cnt += 1;
    }

    std.debug.print("count: {}\n", .{cnt});
}

const Date = struct {
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

fn parseDate(buf: []const u8) !Date {
    if (buf.len != 10) return error.InvalidLength;
    return Date{
        .year = try std.fmt.parseInt(u16, buf[0..4], 10),
        .month = try std.fmt.parseInt(u8, buf[5..7], 10),
        .day = try std.fmt.parseInt(u8, buf[8..10], 10),
    };
}

const Transaction = struct {
    date: Date,
    account: []const u8,
    description: []const u8,
    category: []const u8,
    tags: ?[]const u8,
    amount: f32,

    pub fn format(
        self: Transaction,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s} [{s}] [{s}] {d:.2}", .{
            self.date,
            self.account,
            self.category,
            self.amount,
        });
    }
};

const CsvTransactionIterator = struct {
    buffer: []const u8,
    line_it: ?std.mem.TokenIterator(u8, .scalar) = null,

    const Self = @This();

    pub fn next(self: *Self) ?Transaction {
        if (self.line_it == null) {
            self.line_it = std.mem.tokenizeScalar(u8, self.buffer, '\n');
            _ = self.line_it.?.next(); // skip header line
        }

        if (self.line_it.?.next()) |line| {
            const date = parseDate(line[0..10]) catch |err| {
                std.debug.print("\ndate formatting error ([{s}]): {}\n", .{ line[0..10], err });
                return null;
            };

            if (!std.mem.eql(u8, ",\"", line[10..12])) return null;

            var e = std.mem.indexOfScalarPos(u8, line, 12, '\"') orelse return null;
            const account = line[12..e];

            if (!std.mem.eql(u8, ",\"", line[e + 1 .. e + 3])) return null;
            var s = e + 3;

            e = std.mem.indexOfScalarPos(u8, line, s, '\"') orelse return null;
            const description = line[s..e];

            if (!std.mem.eql(u8, ",\"", line[e + 1 .. e + 3])) return null;
            s = e + 3;

            e = std.mem.indexOfScalarPos(u8, line, s, '\"') orelse return null;
            const category = line[s..e];

            if (line[e + 1] != ',') return null;
            e += 1;
            var tags: ?[]const u8 = null;
            if (line[e + 1] == '\"') {
                s = e + 2;
                e = std.mem.indexOfScalarPos(u8, line, s, '\"') orelse return null;
                tags = line[s..e];
            }

            if (line[e + 1] != ',') return null;
            e += 2;

            const amount = std.fmt.parseFloat(f32, line[e .. line.len - 1]) catch |err| {
                std.debug.print("\namount formatting error ([{s}]): {}\n", .{ line[e .. line.len - 1], err });
                return null;
            };

            return Transaction{
                .date = date,
                .account = account,
                .description = description,
                .category = category,
                .tags = tags,
                .amount = amount,
            };
        } else {
            return null;
        }
    }
};
