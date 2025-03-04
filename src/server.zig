const std = @import("std");

const log = std.log;

const Self = @This();

pub const Config = struct {
    ip: []const u8 = "0.0.0.0",
    port: u16 = 3000,
};

pub const Handler = *const fn (request: *std.http.Server.Request) void;
const BoundHandler = *fn (*const anyopaque, *std.http.Server.Request) void;

// "inspired" by zap
const Callback = union(enum) {
    bound: struct { instance: usize, handler: usize },
    unbound: Handler,
};

addr: std.net.Address,
routes: std.StringHashMap(Callback),
static: std.StringHashMap([]const u8),

pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
    const addr = std.net.Address.resolveIp(config.ip, config.port) catch {
        log.err("error parsing address", .{});
        return error.AddressParseError;
    };
    return .{
        .addr = addr,
        .routes = std.StringHashMap(Callback).init(allocator),
        .static = std.StringHashMap([]const u8).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.routes.deinit();
    self.static.deinit();
}

pub fn handle_static(self: *Self, path: []const u8, source: []const u8) !void {
    if (path.len == 0) return error.EmptyPath;
    if (self.static.contains(path)) return error.AlreadyExists;
    try self.static.put(path, source);
}

pub fn handle(self: *Self, path: []const u8, instance: *anyopaque, handler: anytype) !void {
    if (path.len == 0) {
        return error.EmptyPath;
    }

    if (self.routes.contains(path)) {
        return error.AlreadyExists;
    }

    try self.routes.put(path, Callback{ .bound = .{
        .instance = @intFromPtr(instance),
        .handler = @intFromPtr(handler),
    } });
}

pub fn serve(self: *Self) !void {
    log.info("listening on {}", .{self.addr});

    // note: server never gets deinit()'d here b/c this loop only ever terminates
    // with a Ctrl+C.  so, the port stays in use for a while after program completion
    // the link below shows how to capture this SIGINT...doing the rigth thing in
    // the handler is another story - which i will address when it is too problematic
    //
    // if i want to "catch" a ctrl+c (in linux only)...
    // https://www.reddit.com/r/Zig/comments/11mr0r8/defer_errdefer_and_sigint_ctrlc/
    var server = self.addr.listen(.{}) catch |err| {
        log.err("error listening on addr: {} - {}", .{ self.addr, err });
        return error.AddressListenError;
    };

    while (true) {
        const connection = server.accept() catch |err| {
            log.err("connection accept error - {}", .{err});
            return error.ConnectionAcceptError;
        };

        const thread = try std.Thread.spawn(.{}, handle_connection, .{ self, connection });
        thread.detach();
    }

    std.debug.assert(false);
}

inline fn method_to_slice(method: std.http.Method) []const u8 {
    const byts = std.mem.asBytes(&@intFromEnum(method));
    return std.mem.sliceTo(byts, 0);
}

const READ_BUFFER_SIZE = 8 * 1024;
// const WRITE_BUFFER_SIZE = 8 * 1024;
// const FILE_BUFFER_SIZE = 32 * 1024;

/// this will close the connection when its done
fn handle_connection(self: *Self, connection: std.net.Server.Connection) !void {
    defer {
        connection.stream.close();
        std.log.debug("connection closed.", .{});
    }

    var read_buffer: [READ_BUFFER_SIZE]u8 = undefined;
    var http_server = std.http.Server.init(connection, &read_buffer);

    var keep_alive = true;
    while (keep_alive) {
        var request = http_server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => break,
            else => return err,
        };
        keep_alive = request.head.keep_alive;

        log.info("{s} - {s} ({})", .{
            method_to_slice(request.head.method),
            request.head.target,
            connection.address,
        });

        const route = self.routes.get(request.head.target);

        if (route) |rte| {
            switch (rte) {
                .unbound => |ub| ub(&request),
                .bound => |b| @call(
                    .auto,
                    @as(BoundHandler, @ptrFromInt(b.handler)),
                    .{
                        @as(*anyopaque, @ptrFromInt(b.instance)),
                        &request,
                    },
                ),
            }
        } else {
            // std.log.info("no route found for {s}.", .{request.head.target});
            if (self.static.get(request.head.target)) |st| {
                try request.respond(st, .{
                    .extra_headers = &.{
                        .{ .name = "content-type", .value = "application/javascript" },
                    },
                });
            } else {
                try request.respond("target not found", .{ .status = .not_found });
            }
        }
    }

    // var send_buffer: [WRITE_BUFFER_SIZE]u8 = undefined;

    // var response = request.respondStreaming(
    //     .{
    //         .send_buffer = &send_buffer,
    //         .respond_options = .{
    //             .extra_headers = &.{
    //                 .{ .name = "Content-Type", .value = "text/html" },
    //             },
    //         },
    //     },
    // );

    // var file_buffer: [FILE_BUFFER_SIZE]u8 = undefined;
    // const f = try std.fs.cwd().openFile("html/index.html", .{
    //     .mode = .read_only,
    // });
    // defer f.close();

    // var l: usize = std.math.maxInt(usize);
    // while (l >= FILE_BUFFER_SIZE) {
    //     l = try f.read(&file_buffer);
    //     _ = try response.write(file_buffer[0..l]);
    // }
    // _ = try response.flush();
    // _ = try response.end();

}
