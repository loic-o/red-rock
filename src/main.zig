const std = @import("std");
const Allocator = std.mem.Allocator;
const Data = @import("budget.zig");
const Server = @import("server.zig");
const template = @import("template.zig");

const log = std.log;

var server_ref: ?*Server = null;
fn sigint_handler(sig: c_int) callconv(.C) void {
    std.debug.print("SIGINT ({}) received\n", .{sig});
    if (server_ref) |srvr| {
        srvr.shutdown();
    }
}

pub fn main() !void {
    // Manage the Ctrl + C
    // https://www.reddit.com/r/Zig/comments/11mr0r8/defer_errdefer_and_sigint_ctrlc/
    const act = std.os.linux.Sigaction{
        .handler = .{ .handler = sigint_handler },
        .mask = std.os.linux.empty_sigset,
        .flags = 0,
    };
    if (std.os.linux.sigaction(std.os.linux.SIG.INT, &act, null) != 0) {
        return error.SignalHandlerError;
    }

    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = GPA.allocator();

    const data_dir = blk: {
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        break :blk try std.mem.concat(allocator, u8, &[_][]const u8{ home, "/budget_data" });
    };
    defer allocator.free(data_dir);
    std.log.debug("data dir: {s}", .{data_dir});

    std.log.info("loading data...", .{});
    try Data.init(allocator, data_dir);
    std.log.info("loading complete.", .{});

    // try Data.dump_data(std.io.getStdOut().writer());

    var server = try Server.init(allocator, .{});
    defer server.deinit();
    server_ref = &server;

    var dashboard = try Dashboard.init(allocator);
    defer dashboard.deinit();

    try server.handle("/", &dashboard, &Dashboard.handle);

    try server.serve();

    std.log.debug("returned from serve() loop.", .{});
}

const Dashboard = struct {
    const Self = @This();
    const htmx = @embedFile("templ/index.html");

    allocator: Allocator,
    template: template.Template,

    pub fn init(allocator: Allocator) !Self {
        const templ = try template.from_text(allocator, htmx);
        return .{
            .allocator = allocator,
            .template = templ,
        };
    }

    pub fn deinit(self: *Self) void {
        self.template.deinit();
    }

    pub fn handle(self: *Self, request: *std.http.Server.Request) void {
        self._handle(request) catch |err| {
            // do some error page?
            std.log.err("error handling request: {}", .{err});
        };
    }

    fn _handle(self: *Self, request: *std.http.Server.Request) !void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        const TestData = struct {
            budget: []const f32,
            actual: []const f32,
        };

        const connection = try Data.connect();

        // const budget = [_]f32{ 485.50, 5631.67, 1483.10, 2887.91, 1683.16, 5328.10, 5237.55, 5915.21, 887.00, 3734.41, 3127.81, 1459.79 };
        // const actual = [_]f32{ 3375.73, 4443.81, 3360.66, 5385.53, 3333.24, 4907.49, 5034.22, 5194.89, 4759.88 };
        const budget = connection.get_monthly_totals();
        var actual = connection.get_monthly_actuals();

        for (0..actual.len) |i| {
            actual[i] *= -1;
        }
        // NOTE: not happy about this (or possibly the return value of get_monthly_actuals).  prob need
        // to get current date.  maybe: https://github.com/FObersteiner/zdt
        const lm = std.mem.indexOfScalar(f32, &actual, 0) orelse 11;

        const data = TestData{
            .budget = &budget,
            .actual = actual[0..lm],
        };

        const writer = buffer.writer().any();
        try self.template.render(data, writer);

        try request.respond(buffer.items, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html; charset=utf-8" },
            },
        });
    }
};
