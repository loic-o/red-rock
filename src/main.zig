const std = @import("std");
const http_server = @import("server.zig");
const Template = @import("template.zig");

const log = std.log;

pub fn main() !void {
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = GPA.allocator();

    var server = try http_server.init(allocator, .{});

    var dashboard = try Dashboard.init(allocator);
    defer dashboard.deinit();

    try server.handle("/", &dashboard, &Dashboard.handle);

    try server.serve();
}

const Dashboard = struct {
    const Self = @This();
    const htmx = @embedFile("templ/index.htmx");

    template: Template,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .template = try Template.initText(allocator, htmx),
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
        var buff = std.ArrayList(u8).init(self.allocator);
        defer buff.deinit();

        try self.template.render(buff.writer(), .{});

        try request.respond(buff.items, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
            },
        });
    }
};
