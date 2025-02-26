const std = @import("std");

const StructFieldValue = struct {
    name: []const u8,
    value: FieldValue,
};

const FieldValue = union(enum) {
    Unsupported: void,
    Int: usize,
    Float: f32,
    Bool: bool,
    String: []const u8,
    Slice: struct { allocator: std.mem.Allocator, elements: []FieldValue },
    Struct: struct { allocator: std.mem.Allocator, fields: []StructFieldValue },

    pub fn deinit(self: FieldValue) void {
        switch (self) {
            .Struct => |v| {
                for (v.fields) |f| {
                    v.allocator.free(f.name);
                    f.value.deinit();
                }
                v.allocator.free(v.fields);
            },
            .Slice => |v| {
                for (v.elements) |e| {
                    e.deinit();
                }
                v.allocator.free(v.elements);
            },
            else => {},
        }
    }
};

fn wrap_value(allocator: std.mem.Allocator, value: anytype) !FieldValue {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Int => return .{ .Int = value },
        .Float => return .{ .Float = value },
        .Bool => return .{ .Bool = value },
        .Pointer => |ptr| {
            if (ptr.size == .Slice) {
                switch (@typeInfo(ptr.child)) {
                    .Int => |nfo| {
                        if (nfo.bits == 8) {
                            return .{ .String = value };
                        }
                        return .{ .Unsupported = {} };
                    },
                    else => {
                        var elems = std.ArrayList(FieldValue).init(allocator);
                        errdefer elems.deinit();
                        for (value) |f| {
                            try elems.append(try wrap_value(allocator, f));
                        }
                        return .{ .Slice = .{
                            .allocator = allocator,
                            .elements = try elems.toOwnedSlice(),
                        } };
                    },
                }
            } else return .{ .Unsupported = {} };
        },
        .Struct => {
            var fields = std.ArrayList(StructFieldValue).init(allocator);
            errdefer fields.deinit();
            inline for (@typeInfo(T).Struct.fields) |field| {
                try fields.append(.{
                    .name = try allocator.dupe(u8, field.name),
                    .value = try wrap_value(allocator, @field(value, field.name)),
                });
            }
            return .{ .Struct = .{
                .allocator = allocator,
                .fields = try fields.toOwnedSlice(),
            } };
        },
        else => return .{ .Unsupported = {} },
    }
}

const TemplateElement = union(enum) {
    Static: []const u8,
    Field: []const u8,
    Iterator,
    Section: struct { field: []const u8, children: []TemplateElement },
};

pub const Template = struct {
    allocator: std.mem.Allocator,
    elements: []TemplateElement,

    pub fn deinit(self: Template) void {
        for (self.elements) |elm| {
            _deinit_child(self.allocator, elm);
        }
        self.allocator.free(self.elements);
    }

    fn _deinit_child(allocator: std.mem.Allocator, child: TemplateElement) void {
        if (child == .Section) {
            for (child.Section.children) |ch| {
                _deinit_child(allocator, ch);
            }
            allocator.free(child.Section.children);
        }
    }

    pub fn render(self: Template, data: anytype, writer: std.io.AnyWriter) !void {
        const data_value = try wrap_value(self.allocator, data);
        defer data_value.deinit();
        try _render(self.elements, data_value, writer);
    }

    fn _get_child_field(value: FieldValue, name: []const u8) !StructFieldValue {
        if (value == .Struct) {
            for (value.Struct.fields) |f| {
                if (std.mem.eql(u8, f.name, name)) {
                    return f;
                }
            }
        }
        return error.NotAStruct;
    }

    fn _render(elements: []TemplateElement, data: FieldValue, writer: std.io.AnyWriter) !void {
        for (elements) |elem| {
            switch (elem) {
                .Static => |v| try writer.print("{s}", .{v}),
                .Field => |v| {
                    const fv = try _get_child_field(data, v);
                    try _render_value(fv.value, writer);
                },
                .Section => |v| {
                    const fv = try _get_child_field(data, v.field);
                    switch (fv.value) {
                        .Bool => |b| {
                            if (b) {
                                try _render(v.children, data, writer);
                            }
                        },
                        .Slice => |sl| {
                            if (sl.elements.len > 0) {
                                for (sl.elements) |el| {
                                    try _render(v.children, el, writer);
                                }
                            }
                        },
                        else => return error.InvalidSectionType,
                    }
                },
                .Iterator => {
                    try _render_value(data, writer);
                },
            }
        }
    }

    fn _render_value(value: FieldValue, writer: std.io.AnyWriter) !void {
        switch (value) {
            .String => |v| try writer.print("{s}", .{v}),
            .Float => |v| try writer.print("{d:.2}", .{v}),
            else => try writer.print("<HOLD>", .{}),
        }
    }
};

const ElementList = std.ArrayList(TemplateElement);

const ParseBlock = struct {
    tag: []const u8,
    elements: ElementList,
};

const ElementStack = std.SinglyLinkedList(ParseBlock);
const ElementStackNode = ElementStack.Node;

const ParseContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    stack: ElementStack,

    fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator, .stack = .{} };
    }

    fn push(self: *Self, tag: []const u8) !void {
        const node = try self.allocator.create(ElementStackNode);
        node.*.data = .{
            .tag = tag,
            .elements = ElementList.init(self.allocator),
        };
        self.stack.prepend(node);
    }

    fn pop(self: *Self, tag: []const u8) !ElementList {
        if (self.stack.first) |head| {
            if (std.mem.eql(u8, head.*.data.tag, tag)) {
                if (self.stack.popFirst()) |node| {
                    const list = node.*.data.elements;
                    self.allocator.destroy(node);
                    return list;
                } else return error.StackUnderflow;
            } else {
                std.log.debug("expected: [{s}], got: [{s}].", .{ tag, head.*.data.tag });
                return error.MismatchedSegment;
            }
        } else return error.StackUnderflow;
    }

    fn append(self: *Self, element: TemplateElement) !void {
        if (self.stack.first) |head| {
            try head.*.data.elements.append(element);
        } else {
            return error.StackUnderflow;
        }
    }
};

pub fn from_text(allocator: std.mem.Allocator, source: []const u8) !Template {
    var context = ParseContext.init(allocator);

    try context.push("***");
    _ = try _parse_segment(&context, 0, source);
    var t = try context.pop("***");

    if (context.stack.len() != 0) {
        return error.NonTerminatedSegment;
    }

    return .{
        .allocator = allocator,
        .elements = try t.toOwnedSlice(),
    };
}

fn _parse_segment(context: *ParseContext, start: usize, source: []const u8) !usize {
    var pos = start;
    while (pos < source.len) {
        if (std.mem.indexOfPos(u8, source, pos, "{{")) |ts| {
            if (pos < ts) {
                try context.append(.{ .Static = source[pos..ts] });
            }
            pos = ts + 2;
            if (std.mem.indexOfPos(u8, source, pos, "}}")) |te| {
                switch (source[pos]) {
                    '.' => {
                        try context.append(.{ .Iterator = {} });
                        pos = te + 2;
                    },
                    '#' => {
                        const tag = source[pos + 1 .. te];
                        try context.push(tag);
                        pos = try _parse_segment(context, te + 2, source);
                    },
                    '/' => {
                        const tag = source[pos + 1 .. te];
                        var list = try context.pop(tag);
                        try context.append(.{ .Section = .{
                            .field = tag,
                            .children = try list.toOwnedSlice(),
                        } });
                        return te + 2;
                    },
                    else => {
                        try context.append(.{ .Field = source[pos..te] });
                        pos = te + 2;
                    },
                }
            } else {
                return error.NonTerminatedTag;
            }
        } else {
            break;
        }
    }
    if (pos < source.len - 1) {
        try context.append(.{ .Static = source[pos..] });
    }
    return source.len;
}

test "render test" {
    const expected =
        \\here is some DATA.  enjoy.
        \\123.00, 456.00, 789.00, 
        \\TX:
        \\mon: 100.00
        \\tue: 50.00
        \\
    ;
    var it_sec = [_]TemplateElement{
        .{ .Iterator = {} },
        .{ .Static = ", " },
    };
    var tx_sec = [_]TemplateElement{
        .{ .Field = "desc" },
        .{ .Static = ": " },
        .{ .Field = "value" },
        .{ .Static = "\n" },
    };
    var elms = [_]TemplateElement{
        .{ .Static = "here is some " },
        .{ .Field = "title" },
        .{ .Static = ".  enjoy.\n" },
        .{ .Section = .{
            .field = "numbers",
            .children = &it_sec,
        } },
        .{ .Static = "\nTX:\n" },
        .{ .Section = .{
            .field = "txs",
            .children = &tx_sec,
        } },
    };

    const template = Template{
        .allocator = std.testing.allocator,
        .elements = &elms,
    };

    const T = struct {
        desc: []const u8,
        value: f32,
    };

    const D = struct {
        title: []const u8,
        numbers: []const f32,
        txs: []const T,
    };
    const data = D{
        .title = "DATA",
        .numbers = &[_]f32{ 123, 456, 789 },
        .txs = &[_]T{
            .{ .desc = "mon", .value = 100 },
            .{ .desc = "tue", .value = 50 },
        },
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try template.render(data, buffer.writer().any());

    std.testing.expect(std.mem.eql(u8, expected, buffer.items)) catch |err| {
        std.log.err("got:\n[{s}]\nexpected:\n[{s}]", .{ buffer.items, expected });
        return err;
    };
}

test "parse test" {
    const template_source =
        \\something{{field}}{{#s1}}{{.}}{{#s2}}{{f2}}{{/s2}}{{/s1}}something else.
    ;

    const template = try from_text(std.testing.allocator, template_source);
    defer template.deinit();

    try std.testing.expect(template.elements.len == 4);

    try std.testing.expect(template.elements[2] == .Section);
    try std.testing.expect(template.elements[2].Section.children[0] == .Iterator);

    try std.testing.expect(template.elements[2].Section.children[1].Section.children[0] == .Field);
}
