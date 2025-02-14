const std = @import("std");

const log = std.log;

const Self = @This();

pub const Config = struct {
    ip: []const u8 = "0.0.0.0",
    port: u16 = 3000,
};

pub const Handler = *const fn (request: *std.http.Server.Request) void;

addr: std.net.Address,
routes: std.StringHashMap(Handler),

pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
    const addr = std.net.Address.resolveIp(config.ip, config.port) catch {
        log.err("error parsing address", .{});
        return error.AddressParseError;
    };
    return .{
        .addr = addr,
        .routes = std.StringHashMap(Handler).init(allocator),
    };
}

pub fn serve(self: Self) !void {
    log.info("listening on {}", .{self.addr});
    var server = self.addr.listen(.{}) catch |err| {
        log.err("error listening on addr: {} - {}", .{ self.addr, err });
        return error.AddressListenError;
    };

    // if i want to "catch" a ctrl+c (in linux only)...
    // https://www.reddit.com/r/Zig/comments/11mr0r8/defer_errdefer_and_sigint_ctrlc/

    while (true) {
        const connection = server.accept() catch |err| {
            log.err("connection accept error - {}", .{err});
            return error.ConnectionAcceptError;
        };

        // NOTE: i could implement the use of the std lib std.Thread.Pool
        // for these things - just for giggles
        // docs(?) i found so far:
        //  - https://noelmrtn.fr/posts/zig_threading/
        //  - - https://github.com/NoelM/zig-playground/blob/main/prime_numbers_parallel/prime_std.zig
        const thread = try std.Thread.spawn(.{}, handle_connection, .{ self, connection });
        thread.detach();
    }

    std.debug.assert(false);
}

pub fn get(self: *Self, comptime route: []const u8, handler: Handler) !void {
    try self.routes.put("GET|" ++ route, handler);
}

fn method_to_slice(method: std.http.Method) []const u8 {
    return switch (method) {
        .GET => "GET",
        .PUT => "PUT",
        .HEAD => "HEAD",
        .POST => "POST",
        .TRACE => "TRACE",
        .PATCH => "PATCH",
        .DELETE => "DELETE",
        .CONNECT => "CONNECT",
        .OPTIONS => "OPTIONS",
        else => "I_DUNNO",
    };
}

const READ_BUFFER_SIZE = 8 * 1024;
const WRITE_BUFFER_SIZE = 8 * 1024;
const FILE_BUFFER_SIZE = 32 * 1024;

/// this will close the connection when its done
fn handle_connection(self: Self, connection: std.net.Server.Connection) !void {
    defer connection.stream.close();

    var key_buffer: [256]u8 = undefined;
    var read_buffer: [READ_BUFFER_SIZE]u8 = undefined;
    var http_server = std.http.Server.init(connection, &read_buffer);

    // ignoring 'keep-alive' request unless/until i want to tackle more complex threading
    var request = try http_server.receiveHead();

    log.info("{s} - {s} ({})", .{
        method_to_slice(request.head.method),
        request.head.target,
        connection.address,
    });

    const key = switch (request.head.method) {
        .GET => blk: {
            @memcpy(key_buffer[0..4], "GET|");
            @memcpy(key_buffer[4 .. 4 + request.head.target.len], request.head.target);
            break :blk key_buffer[0 .. 4 + request.head.target.len];
        },
        else => key_buffer[0..1],
    };

    const route = self.routes.get(key);

    if (route) |rte| {
        rte(&request);
    } else {
        std.log.info("no route found for {s}.", .{request.head.target});
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
