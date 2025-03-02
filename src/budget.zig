const std = @import("std");

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
