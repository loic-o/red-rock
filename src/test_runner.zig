const std = @import("std");
const builtin = @import("builtin");

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    const total_start = std.time.milliTimestamp();

    var run_count: usize = 0;
    var pass_count: usize = 0;
    var fail_count: usize = 0;

    for (builtin.test_functions) |t| {
        run_count += 1;

        const start = std.time.milliTimestamp();
        const result = t.func();
        const elapsed = std.time.milliTimestamp() - start;

        const name = extractName(t);
        if (result) |_| {
            pass_count += 1;
            try std.fmt.format(out, "✅ {s} ({d}ms)\n", .{ name, elapsed });
        } else |err| {
            fail_count += 1;
            try std.fmt.format(out, "❌ {s} {}\n", .{ t.name, err });
        }
    }

    const total_elapsed = std.time.milliTimestamp() - total_start;

    try std.fmt.format(out, "Ran {} tests, {} passed, {} failed.\n", .{ run_count, pass_count, fail_count });
    try std.fmt.format(out, "Total run time: {}ms\n", .{total_elapsed});
}

fn extractName(t: std.builtin.TestFn) []const u8 {
    const marker = std.mem.lastIndexOf(u8, t.name, ".test.") orelse return t.name;
    return t.name[marker + 6 ..];
}
