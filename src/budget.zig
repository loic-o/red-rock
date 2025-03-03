const std = @import("std");

const WorksheetIterator = @import("readers.zig").WorksheetIterator;

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

const PlanningData = struct {
    categories: std.ArrayList([]const u8),
    descriptions: std.ArrayList([]const u8),
    amounts: std.ArrayList([12]f32),
};

var data: PlanningData = undefined;

pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !void {
    var dir = try std.fs.openDirAbsolute(data_dir, .{});
    defer dir.close();

    const file = try dir.openFile("worksheet.csv", .{ .mode = .read_only });
    defer file.close();

    var buff_reader = std.io.bufferedReader(file.reader());
    const reader = buff_reader.reader();

    var it = try WorksheetIterator(@TypeOf(reader)).init(allocator, reader);

    data = .{
        .categories = std.ArrayList([]const u8).init(allocator),
        .descriptions = std.ArrayList([]const u8).init(allocator),
        .amounts = std.ArrayList([12]f32).init(allocator),
    };

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
    }
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
