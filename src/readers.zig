const std = @import("std");

const Date = @import("types.zig").Date;
const Transaction = @import("types.zig").Transaction;
const WorksheetLineItem = @import("types.zig").WorksheetLineItem;

pub fn CsvTransactionIterator(ReaderType: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        reader: ReaderType,
        line_buffer: std.ArrayList(u8),
        complete: bool = false,
        current_line: usize = 1,

        pub fn init(allocator: std.mem.Allocator, reader: ReaderType) !Self {
            var self: Self = .{
                .allocator = allocator,
                .reader = reader,
                .line_buffer = std.ArrayList(u8).init(allocator),
            };
            reader.streamUntilDelimiter(self.line_buffer.writer(), '\n', null) catch |err| {
                std.log.err("error reading header line", .{});
                return err;
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.line_buffer.deinit();
        }

        pub fn next(self: *Self) !?Transaction {
            if (self.complete) return null;
            self.current_line += 1;

            self.line_buffer.clearRetainingCapacity();
            self.reader.streamUntilDelimiter(self.line_buffer.writer(), '\n', null) catch |err| switch (err) {
                error.EndOfStream => self.complete = true,
                else => return err,
            };

            const line = self.line_buffer.items;

            const date = Date.parse_date(line[0..10]) catch |err| {
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
        }
    };
}

pub fn WorksheetIterator(ReaderType: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        reader: ReaderType,
        line_buffer: std.ArrayList(u8),
        amt_buffer: [12]f32 = undefined,
        complete: bool = false,
        current_line: usize = 0,

        pub fn init(allocator: std.mem.Allocator, reader: ReaderType) !Self {
            var self: Self = .{
                .allocator = allocator,
                .reader = reader,
                .line_buffer = std.ArrayList(u8).init(allocator),
            };
            reader.streamUntilDelimiter(self.line_buffer.writer(), '\n', null) catch |err| {
                std.log.err("error reading header line", .{});
                return err;
            };
            // std.log.debug("read header line", .{});
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.line_buffer.deinit();
        }

        pub fn next(self: *Self) !?WorksheetLineItem {
            if (self.complete) return null;
            self.current_line += 1;

            self.line_buffer.clearRetainingCapacity();
            self.reader.streamUntilDelimiter(self.line_buffer.writer(), '\n', null) catch |err| switch (err) {
                error.EndOfStream => self.complete = true,
                else => return err,
            };

            if (std.mem.trim(u8, self.line_buffer.items, " ").len == 0) {
                return null;
            }

            var ws_item = WorksheetLineItem{
                .amounts = self.amt_buffer[0..],
            };

            var p = std.mem.indexOfScalar(u8, self.line_buffer.items, ',') orelse {
                std.log.debug("failed to locate category on line:\n{} | {s}", .{ self.current_line, self.line_buffer.items });
                return error.InvalidFormat;
            };
            ws_item.category = self.line_buffer.items[0..p];
            p += 1;

            var e = std.mem.indexOfScalarPos(u8, self.line_buffer.items, p, ',') orelse return error.InvalidFormat;
            ws_item.description = self.line_buffer.items[p..e];
            p = e + 1;

            for (0..12) |i| {
                e = std.mem.indexOfScalarPos(u8, self.line_buffer.items, p, ',') orelse return error.InvalidFormat;
                if (e == p) {
                    self.amt_buffer[i] = 0.0;
                } else {
                    const t = std.mem.trim(u8, self.line_buffer.items[p + 1 .. e], " ");
                    if (t.len == 0) {
                        self.amt_buffer[i] = 0.0;
                    } else {
                        self.amt_buffer[i] = std.fmt.parseFloat(f32, t) catch |err| {
                            std.log.debug("failed to parse [{s}] ({},{})", .{ t, p, e });
                            return err;
                        };
                    }
                }
                p = e + 1;
            }

            return ws_item;
        }
    };
}

test "worksheet test" {
    const test_data =
        \\Category,Purpose,January,Feb,Mar,etc...
        \\Utilities,Because,$20.00,$21.00,$22.00,$23.00,$24.00,$25.00,$26.00,$27.00,$28.00,$29.00,$30.00,$31.00,,,,,
        \\Groceries,For the Food,$30.00,$31.00,$32.00,$33.00,$34.00,,$36.00,$37.00,$38.00,$39.00,$40.00,$41.00,,,,,
        \\Travel,For the Fun,$40.00,$41.00,$42.00,$43.00,$44.00,$45.00,$46.00,$47.00,$48.00,$49.00,$50.00,$51.00,,,,,
    ;

    var stream = std.io.fixedBufferStream(test_data);
    const reader = stream.reader();

    var worksheet_file_iterator = try WorksheetIterator(@TypeOf(reader)).init(std.testing.allocator, reader);
    defer worksheet_file_iterator.deinit();

    var item = try worksheet_file_iterator.next();
    try std.testing.expect(item != null);
    try std.testing.expect(item.?.amounts[2] == 22.00);

    item = try worksheet_file_iterator.next();
    try std.testing.expect(item != null);
    try std.testing.expect(item.?.amounts[11] == 41.00);

    item = try worksheet_file_iterator.next();
    try std.testing.expect(item != null);
    try std.testing.expect(std.mem.eql(u8, "For the Fun", item.?.description));

    try std.testing.expect(try worksheet_file_iterator.next() == null);
}
