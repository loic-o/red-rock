const std = @import("std");
const Allocator = std.mem.Allocator;
const http_server = @import("server.zig");
const Template = @import("template.zig").Template;

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

    allocator: Allocator,
    template: Template,

    pub fn init(allocator: Allocator) !Self {
        return .{
            .allocator = allocator,
            .template = try Template.fromText(allocator, htmx),
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

        try self.template.render(void, {}, buffer.writer().any());

        try request.respond(buffer.items, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
            },
        });
    }
};
