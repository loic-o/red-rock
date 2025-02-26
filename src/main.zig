const std = @import("std");
const Allocator = std.mem.Allocator;
const http_server = @import("server.zig");

const log = std.log;

pub fn main() !void {
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = GPA.allocator();

    var server = try http_server.init(allocator, .{});

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

    pub fn init(allocator: Allocator) !Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *Self) void {}

    pub fn handle(self: *Self, request: *std.http.Server.Request) void {
        self._handle(request) catch |err| {
            // do some error page?
            std.log.err("error handling request: {}", .{err});
        };
    }

    fn _handle(_: *Self, request: *std.http.Server.Request) !void {
        try request.respond(htmx, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
            },
        });
    }
};
