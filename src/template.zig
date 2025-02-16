const std = @import("std");

const FieldType = enum {
    Float,
};

const FieldValue = union(enum) {
    Unsupported: void,
    NotFound: void,
    Void: void,
    Int: usize,
    Float: f32,
    Bool: bool,
    String: []const u8,
    Slice: struct { ptr: [*]const u8, len: usize, type: FieldType },
};

fn get_field_value(comptime T: type, instance: T, field_name: []const u8) FieldValue {
    if (@typeInfo(T) == .Void) return .{ .Void = {} };
    inline for (@typeInfo(T).Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            switch (@typeInfo(field.type)) {
                .Int => return .{ .Int = @field(instance, field.name) },
                .Float => return .{ .Float = @field(instance, field.name) },
                .Bool => return .{ .Bool = @field(instance, field.name) },
                .Pointer => |ptr| {
                    if (ptr.size == .Slice) {
                        switch (@typeInfo(ptr.child)) {
                            .Int => |nfo| {
                                if (nfo.bits == 8) {
                                    return .{ .String = @field(instance, field.name) };
                                }
                                return .{ .Unsupported = {} };
                            },
                            .Float => {
                                const slice = @field(instance, field.name);
                                return .{ .Slice = .{
                                    .ptr = @as([*]const u8, @alignCast(@ptrCast(slice.ptr))),
                                    .len = slice.len,
                                    .type = .Float,
                                } };
                            },
                            else => return .{ .Unsupported = {} },
                        }
                    } else return .{ .Unsupported = {} };
                },
                else => return .{ .Unsupported = {} },
            }
        }
    }
    return .{ .NotFound = {} };
}

const TemplateElement = union(enum) {
    Static: []const u8,
    Var: []const u8,
    Iterator: void,
    Section: []const u8,
    End: []const u8,

    pub fn format(value: TemplateElement, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (value) {
            .Static => |v| try writer.print("{s}", .{v}),
            .Var => |v| try writer.print("{{{{{s}}}}}", .{v}),
            .Iterator => try writer.print("{{{{.}}}}", .{}),
            .Section => |v| try writer.print("{{{{#{s}}}}}", .{v}),
            .End => |v| try writer.print("{{{{/{s}}}}}", .{v}),
        }
    }
};

pub const Template = struct {
    const Self = @This();

    template: []const u8,
    elements: std.ArrayList(TemplateElement),

    pub fn fromText(allocator: std.mem.Allocator, template: []const u8) !Template {
        var elements = std.ArrayList(TemplateElement).init(allocator);

        const st_tm = std.time.microTimestamp();
        var pos: usize = 0;
        while (pos < template.len) {
            if (std.mem.indexOfPos(u8, template, pos, "{{")) |ts| {
                if (ts > pos) {
                    try elements.append(.{ .Static = template[pos..ts] });
                }
                if (std.mem.indexOfPos(u8, template, ts + 2, "}}")) |te| {
                    const tag_text = template[ts + 2 .. te];
                    if (tag_text.len == 1 and tag_text[0] == '.') {
                        try elements.append(.{ .Iterator = {} });
                    } else if (tag_text.len > 1 and tag_text[0] == '#') {
                        try elements.append(.{ .Section = tag_text[1..] });
                    } else if (tag_text.len > 0 and tag_text[0] == '/') {
                        try elements.append(.{ .End = tag_text[1..] });
                    } else {
                        try elements.append(.{ .Var = tag_text });
                    }
                    pos = te + 2;
                } else {
                    return error.UnterminatedTag;
                }
            } else {
                try elements.append(.{ .Static = template[pos..] });
                break;
            }
        }
        const el_tm = std.time.microTimestamp() - st_tm;
        std.log.debug("parsed in {}us", .{el_tm});

        return .{
            .template = template,
            .elements = elements,
        };
    }

    pub fn deinit(self: *Self) void {
        self.elements.deinit();
    }
    pub fn render(self: Self, T: type, data: T, writer: std.io.AnyWriter) !void {
        const st_tm = std.time.microTimestamp();
        for (self.elements.items) |elem| {
            switch (elem) {
                .Static => |txt| try writer.writeAll(txt),
                .Var => |tag| {
                    switch (get_field_value(T, data, tag)) {
                        .Int => |v| try writer.print("{}", .{v}),
                        .Float => |v| try writer.print("{d:.2}", .{v}),
                        .Bool => |v| try writer.print("{}", .{v}),
                        .String => |v| try writer.print("{s}", .{v}),
                        .Slice => |v| {
                            switch (v.type) {
                                .Float => {
                                    const p = @as([*]f32, @alignCast(@constCast(@ptrCast(v.ptr))));
                                    for (0..v.len) |i| {
                                        if (i > 0) try writer.print(",", .{});
                                        try writer.print("{d:.2}", .{p[i]});
                                    }
                                },
                            }
                        },
                        else => std.log.info("!!{s}!! :: var of 'other' type", .{tag}),
                    }
                },
                else => std.log.info("can't render {} right now", .{elem}),
            }
        }
        const el_tm = std.time.microTimestamp() - st_tm;
        std.log.debug("rendered in {}us", .{el_tm});
    }
};

const Data = struct {
    string: []const u8 = undefined,
    int1: usize = undefined,
    float1: f32 = undefined,
    slfl: []f32 = undefined,
    cslfl: []const f32 = undefined,
};

test "templ: void template" {
    const expected = "this is a test";
    var template = try Template.fromText(std.testing.allocator, expected);
    defer template.deinit();

    var output_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer output_buffer.deinit();

    try template.render(void, {}, output_buffer.writer().any());

    std.testing.expect(std.mem.eql(u8, expected, output_buffer.items)) catch {
        const out = std.io.getStdOut().writer();
        try out.print("expected:\n[{s}]\ngot:\n[{s}]\n.", .{ expected, output_buffer.items });
    };
}

test "templ: basic" {
    const data = Data{
        .string = "string value",
        .int1 = 42,
        .float1 = std.math.pi,
    };

    const templ =
        \\str: -->{{string}}<--
        \\int1: -->{{int1}}<--
        \\float1: -->{{float1}}<--
    ;
    const expected =
        \\str: -->string value<--
        \\int1: -->42<--
        \\float1: -->3.14<--
    ;

    var output_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer output_buffer.deinit();

    var template = try Template.fromText(std.testing.allocator, templ);
    defer template.deinit();

    try template.render(Data, data, output_buffer.writer().any());

    std.testing.expect(std.mem.eql(u8, expected, output_buffer.items)) catch {
        const out = std.io.getStdOut().writer();
        try out.print("expected:\n[{s}]\ngot:\n[{s}]\n.", .{ expected, output_buffer.items });
    };
}

test "templ: slice of floats" {
    const fls = [_]f32{ 123, 456, 789 };
    const data = Data{
        .string = "string value",
        .int1 = 42,
        .float1 = std.math.pi,
        .cslfl = fls[0..],
    };

    const templ =
        \\begin:
        \\{{#cslfl}}
        \\{{.}}
        \\{{/cslfl}}
        \\:end
    ;
    const expected =
        \\begin:
        \\123
        \\456
        \\789
        \\:end
    ;

    var output_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer output_buffer.deinit();

    var template = try Template.fromText(std.testing.allocator, templ);
    defer template.deinit();

    try template.render(Data, data, output_buffer.writer().any());

    std.testing.expect(std.mem.eql(u8, expected, output_buffer.items)) catch {
        const out = std.io.getStdOut().writer();
        try out.print("expected:\n[{s}]\ngot:\n[{s}]\n.", .{ expected, output_buffer.items });
    };
}
