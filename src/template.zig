const std = @import("std");

const Span = union(enum) {
    // Static: struct { start: usize, len: usize },
    Static: []const u8,
    Var: []const u8,
    Iter: void,
    Section: []const u8,
    Placeholder: struct { start: usize, len: usize },
};

pub fn Template(comptime T: type) type {
    return struct {
        const Self = @This();
        const DataType: type = T;

        templ_text: []const u8,
        spans: std.ArrayList(Span),

        pub fn init(allocator: std.mem.Allocator, templ: []const u8) !Self {
            const spans = try parse(allocator, templ);
            return .{
                .spans = spans,
                .templ_text = templ,
            };
        }

        fn parse(allocator: std.mem.Allocator, templ: []const u8) !std.ArrayList(Span) {
            var spans = std.ArrayList(Span).init(allocator);

            var start: ?usize = null;

            var i: usize = 0;
            while (i < templ.len) {
                if (templ[i] == '{' and templ[i + 1] == '{') {
                    // if we were reading static text add a span for it
                    if (start) |s| {
                        try spans.append(.{ .Static = templ[s..i] });
                        start = null;
                    }
                    const st = i + 2;
                    var j = st;
                    const complete: bool = while (j < templ.len) : (j += 1) {
                        if (templ[j] == '}' and templ[j + 1] == '}') {
                            const tv = templ[st..j];
                            if (std.mem.eql(u8, tv, ".")) {
                                // iterator
                                try spans.append(.{ .Iter = {} });
                            } else if (tv[0] == '#') {
                                // section
                                try spans.append(.{ .Section = templ[st..j] });
                            } else {
                                // variable
                                try spans.append(.{ .Var = templ[st..j] });
                            }
                            i = j + 2;
                            break true;
                        }
                    } else false;
                    if (!complete) {
                        return error.UnterminatedTag;
                    }
                } else {
                    if (start) |_| {} else {
                        start = i;
                    }
                    i += 1;
                }
            }
            // if we were reading a static text add a span for it
            if (start) |s| {
                try spans.append(.{ .Static = templ[s..templ.len] });
            }

            return spans;
        }

        pub fn deinit(self: *Self) void {
            self.spans.deinit();
        }

        pub fn render(self: Self, data: T, writer: anytype) !void {
            for (self.spans.items) |span| {
                switch (span) {
                    .Static => |val| {
                        _ = try writer.write(val);
                    },
                    .Var => |v| {
                        // std.log.debug("rendering Var, {}, {}", .{ v.start, v.len });
                        const val = get_field_value(data, v);
                        switch (val) {
                            .Int => |i| try writer.print("{}", .{i}),
                            .Float => |f| try writer.print("{}", .{f}),
                            .String => |s| try writer.print("{s}", .{s}),
                            .None => {},
                        }
                    },
                    .Iter => {},
                    .Section => {},
                    .Placeholder => |_| {},
                }
            }
        }

        fn get_field_value(instance: T, fieldName: []const u8) FieldValue {
            if (@typeInfo(T) != .Struct) @compileError(@typeName(T) ++ " is not a struct");
            inline for (@typeInfo(T).Struct.fields) |field| {
                if (std.mem.eql(u8, field.name, fieldName)) {
                    // Here, we're using the field type to determine which union field to use
                    switch (@typeInfo(field.type)) {
                        .Int => return .{ .Int = @field(instance, field.name) },
                        .Float => return .{ .Float = @field(instance, field.name) },
                        .Pointer => |ptr| {
                            if (ptr.size == .Slice) {
                                if (ptr.child == u8) {
                                    // makes sense to have a special case for Strings IMO
                                    const str = @field(instance, field.name);
                                    return .{ .String = str };
                                } else {
                                    const slice = @field(instance, field.name);
                                    return .{ .Slice = .{
                                        .ptr = @as([*]const u8, @alignCast(slice.ptr)),
                                        .len = slice.len,
                                        .type = @typeInfo(ptr.child),
                                    } };
                                }
                            } else {
                                // what is left out by this?
                                // - a single item pointer to data somewhere...dont need this right now
                                // - an actual array in the data...i will just require slices for now
                                std.log.debug("unspported pointer type", .{});
                            }
                        },
                        else => {
                            std.log.debug("unsupported field type", .{});
                            return .None;
                        },
                    }
                }
            }
            return .None; // Field not found
        }
    };
}

const FieldValue = union(enum) {
    Int: usize,
    Float: f32,
    String: []const u8,
    Slice: struct { ptr: [*]const u8, len: usize, type: std.builtin.Type },
    None: void,
};

// test "templ: test get field" {
//     const S = struct {
//         field_one: usize,
//         field_two: usize,
//         field_three: usize,
//     };
//     const s: S = .{ .field_one = 1, .field_two = 2, .field_three = 3 };
//
//     try std.testing.expect(get_field_value(S, s, "field_two").Int == 2);
// }

test "templ: simple parse 1" {
    const templ =
        \\this is a templ
        \\with a couple of lines
    ;
    var template = try Template(void).init(std.testing.allocator, templ);
    defer template.deinit();

    try std.testing.expect(template.spans.items.len == 1);
    try std.testing.expect(std.mem.eql(
        u8,
        "this is a templ\nwith a couple of lines",
        template.spans.items[0].Static,
    ));
}

test "templ: simple parse 2" {
    const templ =
        \\this is a template
        \\{{tag}}
        \\and the ending
    ;
    var template = try Template(void).init(std.testing.allocator, templ);
    defer template.deinit();

    std.testing.expect(template.spans.items.len == 3) catch return error.NotEnoughSpans;

    const ph = template.spans.items[1].Var;
    std.testing.expect(std.mem.eql(u8, "tag", ph)) catch return error.BadTagParse;
}

test "templ: basic render" {
    const templ =
        \\my name is {{name}}.
    ;

    const Data = struct {
        name: []const u8,
    };
    const data = Data{
        .name = "loic",
    };

    var template = try Template(Data).init(std.testing.allocator, templ);
    defer template.deinit();

    var buff = std.ArrayList(u8).init(std.testing.allocator);
    defer buff.deinit();

    try template.render(data, buff.writer());

    std.testing.expect(buff.items.len == 16) catch {
        std.log.debug("rendered: {s}\n  len: {}, expected 16.\n", .{
            buff.items,
            buff.items.len,
        });
        return error.WrongRenderLength;
    };
}
