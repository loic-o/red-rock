/// NOT USING THIS
/// (yet), but just for reference: https://ziggit.dev/t/simple-http-server/4487
///
const std = @import("std");
const http_server = @import("server.zig");
const Template = @import("template.zig");

const log = std.log;

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = GPA.allocator();

pub fn main() !void {
    var server = try http_server.init(allocator, .{});

    try server.get("/", default_page);

    try server.serve();
}

fn default_page(request: *std.http.Server.Request) void {
    const txt = @embedFile("templ/index.htmx");
    var index_templ = Template.initText(allocator, txt) catch |err| {
        std.log.err("error loading index.htmx: {}", .{err});
        return;
    };
    defer index_templ.deinit();

    var buff = std.ArrayList(u8).init(allocator);
    defer buff.deinit();

    index_templ.render(buff.writer(), .{}) catch |err| {
        std.log.err("error rendering index.htmx: {}", .{err});
        return;
    };

    request.respond(buff.items, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/html" },
        },
    }) catch |err| {
        std.log.err("error sending response: {}", .{err});
    };
}

// fn dump_xaction_file() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();
//
//     var args_it = std.process.args();
//     _ = args_it.next();
//     const data_dir = args_it.next() orelse "/home/loico/budget_data";
// }
