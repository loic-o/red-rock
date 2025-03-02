const std = @import("std");
const Allocator = std.mem.Allocator;
const Server = @import("server.zig");
const template = @import("template.zig");

const log = std.log;

// var server_ref: ?*Server = null;
// fn sigint_handler(sig: c_int) callconv(.C) void {
//     std.debug.print("SIGINT ({}) received\n", .{sig});
//     if (server_ref) |srvr| {
//         // this causes a panic from within the accept() call...
//         srvr.deinit();
//     }
// }

pub fn main() !void {
    // Manage the Ctrl + C
    // const act = std.os.linux.Sigaction{
    //     .handler = .{ .handler = sigint_handler },
    //     .mask = std.os.linux.empty_sigset,
    //     .flags = 0,
    // };
    // if (std.os.linux.sigaction(std.os.linux.SIG.INT, &act, null) != 0) {
    //     return error.SignalHandlerError;
    // }

    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = GPA.allocator();

    const data_dir = blk: {
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        break :blk try std.mem.concat(allocator, u8, &[_][]const u8{ home, "/budget_data" });
    };
    defer allocator.free(data_dir);
    std.log.debug("data dir: {s}", .{data_dir});

    var server = try Server.init(allocator, .{});
    // server_ref = &server;

    var dashboard = try Dashboard.init(allocator);
    defer dashboard.deinit();

    try server.handle_static("/js/util.js", @embedFile("static/util.js"));
    try server.handle("/", &dashboard, &Dashboard.handle);

    try server.serve();
}

const Dashboard = struct {
    const Self = @This();
    const htmx = @embedFile("templ/index.htmx");

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

        const Data = struct {
            budget: []const f32,
            actual: []const f32,
        };

        const budget = [_]f32{ 485.50, 5631.67, 1483.10, 2887.91, 1683.16, 5328.10, 5237.55, 5915.21, 887.00, 3734.41, 3127.81, 1459.79 };
        const actual = [_]f32{ 3375.73, 4443.81, 3360.66, 5385.53, 3333.24, 4907.49, 5034.22, 5194.89, 4759.88 };

        const data = Data{
            .budget = &budget,
            .actual = &actual,
        };

        const writer = buffer.writer().any();
        try self.template.render(data, writer);

        try request.respond(buffer.items, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
            },
        });
    }
};
