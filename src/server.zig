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
server: std.net.Server = undefined,
running: std.atomic.Value(bool),

pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
    const addr = std.net.Address.resolveIp(config.ip, config.port) catch {
        log.err("error parsing address", .{});
        return error.AddressParseError;
    };
    const srvr = addr.listen(.{ .reuse_port = true }) catch |err| {
        log.err("error listening on addr: {} - {}", .{ addr, err });
        return error.AddressListenError;
    };
    return .{
        .addr = addr,
        .routes = std.StringHashMap(Callback).init(allocator),
        .running = std.atomic.Value(bool).init(true),
        .server = srvr,
    };
}

pub fn shutdown(self: *Self) void {
    // this will get the serve loop to end once it deals with the next connection
    self.running.store(false, .seq_cst);
    // we will gitve it another connection to force that to happen
    std.log.debug("sending terminating request", .{});
    const c: ?std.net.Stream = std.net.tcpConnectToAddress(self.addr) catch blk: {
        // probably fine...for now assume its because the to loop ended already by way of another connection...
        std.log.debug("terminating request FAILED.", .{});
        break :blk null;
    };
    if (c) |cc| {
        std.log.debug("connected...", .{});
        std.time.sleep(std.time.ns_per_s / 2);
        cc.close();
    }
}

pub fn deinit(self: *Self) void {
    std.log.debug("server cleaning up.", .{});
    self.routes.deinit();
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

    while (self.running.load(.seq_cst)) {
        const connection = self.server.accept() catch |err| {
            log.err("connection accept error - {}", .{err});
            return error.ConnectionAcceptError;
        };

        if (self.running.load(.seq_cst)) {
            const thread = try std.Thread.spawn(.{}, handle_connection, .{ self, connection });
            thread.detach();
        } else {
            std.log.debug("ignoring latest request due to shutdown request.", .{});
            connection.stream.close();
        }
    }
    self.server.deinit();
    std.log.debug("returning from serve", .{});
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
            handle_static(self, &request) catch |err| switch (err) {
                std.fs.File.OpenError.FileNotFound => try request.respond("oops", .{ .status = .not_found }),
                else => return err,
            };
        }
    }
}

const WRITE_BUFFER_SIZE: usize = 8 * 1024;
const FILE_BUFFER_SIZE: usize = 8 * 1024;

fn handle_static(_: *Self, request: *std.http.Server.Request) !void {
    var send_buffer: [WRITE_BUFFER_SIZE]u8 = undefined;
    var file_buffer: [FILE_BUFFER_SIZE]u8 = undefined;

    std.mem.copyForwards(u8, &file_buffer, "src");
    std.mem.copyForwards(u8, file_buffer[3..], request.head.target);
    const file_path = file_buffer[0 .. request.head.target.len + 3];

    const f = std.fs.cwd().openFile(file_path, .{
        .mode = .read_only,
    }) catch |err| {
        std.log.debug("{}: trying to server static: {s}", .{ err, file_path });
        return err;
    };
    defer f.close();

    var response = request.respondStreaming(
        .{
            .send_buffer = &send_buffer,
            .respond_options = .{
                .extra_headers = &.{
                    .{ .name = "Content-Type", .value = "application/javascript; charset=utf-8" },
                },
            },
        },
    );

    var l: usize = std.math.maxInt(usize);
    while (l >= FILE_BUFFER_SIZE) {
        l = try f.read(&file_buffer);
        _ = try response.write(file_buffer[0..l]);
    }
    _ = try response.flush();
    _ = try response.end();
}
