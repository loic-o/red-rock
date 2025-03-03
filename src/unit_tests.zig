test "container" {
    _ = @import("template.zig");
    _ = @import("readers.zig");
}

const std = @import("std");

test "array copy" {
    var one = [_]usize{ 1, 2, 3, 4 };
    const two = one;

    try std.testing.expect(two[0] == one[0]);

    one[1] = 9;
    try std.testing.expect(two[1] == 2);
}
