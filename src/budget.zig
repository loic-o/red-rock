const std = @import("std");

const Date = @import("types.zig").Date;
const WorksheetIterator = @import("readers.zig").WorksheetIterator;
const TransactionIterator = @import("readers.zig").CsvTransactionIterator;

pub fn connect() !Connection {
    return .{};
}

pub const Connection = struct {
    pub fn get_monthly_totals(_: Connection) [12]f32 {
        var res: [12]f32 = undefined;
        for (0..12) |i| {
            res[i] = 0;
            for (0..data.amounts.items.len) |j| {
                res[i] += data.amounts.items[j][i];
            }
        }
        return res;
    }

    pub fn get_monthly_actuals(_: Connection) [12]f32 {
        var res = [_]f32{0} ** 12;
        for (data.tx_dates.items, 0..) |dt, i| {
            res[dt.month - 1] += data.tx_amounts.items[i];
        }
        return res;
    }
};

const PlanningData = struct {
    categories: std.ArrayList([]const u8),
    descriptions: std.ArrayList([]const u8),
    amounts: std.ArrayList([12]f32),

    tx_dates: std.ArrayList(Date),
    tx_accounts: std.ArrayList([]const u8),
    tx_descriptions: std.ArrayList([]const u8),
    tx_categories: std.ArrayList([]const u8),
    tx_amounts: std.ArrayList(f32),
};

var data: PlanningData = undefined;

pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !void {
    data = .{
        .categories = std.ArrayList([]const u8).init(allocator),
        .descriptions = std.ArrayList([]const u8).init(allocator),
        .amounts = std.ArrayList([12]f32).init(allocator),

        .tx_dates = std.ArrayList(Date).init(allocator),
        .tx_accounts = std.ArrayList([]const u8).init(allocator),
        .tx_descriptions = std.ArrayList([]const u8).init(allocator),
        .tx_categories = std.ArrayList([]const u8).init(allocator),
        .tx_amounts = std.ArrayList(f32).init(allocator),
    };

    var dir = try std.fs.openDirAbsolute(data_dir, .{});
    defer dir.close();

    const ws_file = try dir.openFile("worksheet.csv", .{ .mode = .read_only });
    var cnt = try _load_worksheet(allocator, ws_file);
    std.log.info("loaded {} worksheet items.", .{cnt});

    const tx_file = try dir.openFile("transactions_001.csv", .{ .mode = .read_only });
    cnt = try _load_transactions(allocator, tx_file);
    std.log.info("loaded {} transactions.", .{cnt});
}

fn _load_worksheet(allocator: std.mem.Allocator, file: std.fs.File) !usize {
    defer file.close();

    var buff_reader = std.io.bufferedReader(file.reader());
    const reader = buff_reader.reader();

    var it = try WorksheetIterator(@TypeOf(reader)).init(allocator, reader);

    var cnt: usize = 0;

    while (try it.next()) |item| {
        if (item.category.len == 0) continue;

        const cat = try allocator.dupe(u8, item.category);
        errdefer allocator.free(cat);

        const desc = try allocator.dupe(u8, item.description);
        errdefer allocator.free(desc);

        var amts: [12]f32 = undefined;
        std.debug.assert(item.amounts.len == 12);
        std.mem.copyForwards(f32, &amts, item.amounts);

        try data.categories.append(cat);
        try data.descriptions.append(desc);
        try data.amounts.append(amts);

        cnt += 1;
    }

    return cnt;
}

fn _load_transactions(allocator: std.mem.Allocator, file: std.fs.File) !usize {
    defer file.close();

    var buff_reader = std.io.bufferedReader(file.reader());
    const reader = buff_reader.reader();

    var it = try TransactionIterator(@TypeOf(reader)).init(allocator, reader);

    var cnt: usize = 0;

    while (try it.next()) |tx| {
        const acc = try allocator.dupe(u8, tx.account);
        errdefer allocator.free(acc);

        const des = try allocator.dupe(u8, tx.description);
        errdefer allocator.free(des);

        const cat = try allocator.dupe(u8, tx.category);
        errdefer allocator.free(cat);

        try data.tx_dates.append(tx.date);
        try data.tx_accounts.append(acc);
        try data.tx_descriptions.append(des);
        try data.tx_categories.append(cat);
        try data.tx_amounts.append(tx.amount);

        cnt += 1;
    }

    return cnt;
}

pub fn dump_data(writer: anytype) !void {
    var c: usize = 0;
    for (0..data.categories.items.len) |i| {
        c += 1;
        try writer.print("{:>2} {s}, {s}, ", .{ c, data.categories.items[i], data.descriptions.items[i] });
        for (0..12) |j| {
            try writer.print("{d}, ", .{data.amounts.items[i][j]});
        }
        _ = try writer.write("\n");
    }
}
