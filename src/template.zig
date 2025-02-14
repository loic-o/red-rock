const std = @import("std");

const Self = @This();

templ_text: []const u8,
spans: std.ArrayList(Span),

pub const LoadArgTag = enum {
    filename,
    text,
};

pub const LoadArgs = union(LoadArgTag) {
    filename: []const u8,
    text: []const u8,
};

const Span = union(enum) {
    Static: struct { start: usize, len: usize },
    Var: struct { start: usize, len: usize },
    Placeholder: struct { start: usize, len: usize },
};

pub fn initText(allocator: std.mem.Allocator, templ: []const u8) !Self {
    return try init(allocator, .{ .text = templ });
}

pub fn init(allocator: std.mem.Allocator, args: LoadArgs) !Self {
    const templ = switch (args) {
        .filename => |fi| fi,
        .text => |tx| tx,
    };

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
            if (start) |s| {
                try spans.append(.{ .Static = .{
                    .start = s,
                    .len = i - s,
                } });
                start = null;
            }
            const st = i + 2;
            var j = st;
            const complete: bool = while (j < templ.len) : (j += 1) {
                if (templ[j] == '}' and templ[j + 1] == '}') {
                    try spans.append(.{ .Var = .{
                        .start = st,
                        .len = j - st,
                    } });
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
    if (start) |s| {
        try spans.append(.{ .Static = .{
            .start = s,
            .len = templ.len - s,
        } });
    }

    return spans;
}

pub fn deinit(self: *Self) void {
    self.spans.deinit();
}

pub fn render(self: Self, writer: anytype, data: anytype) !void {
    for (self.spans.items) |span| {
        switch (span) {
            .Static => |i| {
                // std.log.debug("rendering Static, {}, {}", .{ i.start, i.len });
                _ = try writer.write(self.templ_text[i.start .. i.start + i.len]);
            },
            .Var => |v| {
                // std.log.debug("rendering Var, {}, {}", .{ v.start, v.len });
                const val = get_field_value(data, self.templ_text[v.start .. v.start + v.len]);
                switch (val) {
                    .Int => |i| try writer.print("{}", .{i}),
                    .Float => |f| try writer.print("{}", .{f}),
                    .String => |s| try writer.print("{s}", .{s}),
                    .None => {},
                }
            },
            .Placeholder => |_| {},
        }
    }
}

const FieldValue = union(enum) {
    Int: usize,
    Float: f32,
    String: []const u8,
    None: void,
};

fn get_field_value(instance: anytype, fieldName: []const u8) FieldValue {
    const StructInfo = @TypeOf(instance);
    if (@typeInfo(StructInfo) != .Struct) @compileError(@typeName(StructInfo) ++ " is not a struct");
    inline for (@typeInfo(StructInfo).Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, fieldName)) {
            // Here, we're using the field type to determine which union field to use
            switch (@typeInfo(field.type)) {
                .Int => return .{ .Int = @field(instance, field.name) },
                .Float => return .{ .Float = @field(instance, field.name) },
                .Pointer => |ptr| {
                    if (ptr.size == .Slice and ptr.child == u8) {
                        const str = @field(instance, field.name);
                        // std.log.debug("field [{s}] = [{s}]", .{ field.name, str });
                        return .{ .String = str };
                    } else {
                        std.log.debug("unspported field pointer type", .{});
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

test "templ: no tags" {
    const templ =
        \\this is a templ
        \\with a couple of lines
    ;
    var template = try initText(std.testing.allocator, templ);
    defer template.deinit();

    try std.testing.expect(template.spans.items.len == 1);
    try std.testing.expect(template.spans.items[0].Static.start == 0);
    try std.testing.expect(template.spans.items[0].Static.len == templ.len);
}

test "templ: mid tag" {
    const templ =
        \\this is a template
        \\{{tag}}
        \\and the ending
    ;
    var template = try initText(std.testing.allocator, templ);
    defer template.deinit();

    std.testing.expect(template.spans.items.len == 3) catch return error.NotEnoughSpans;

    const ph = template.spans.items[1].Var;
    std.testing.expect(std.mem.eql(u8, "tag", templ[ph.start .. ph.start + ph.len])) catch return error.BadTagParse;
}

test "templ: test get field" {
    const S = struct {
        field_one: usize,
        field_two: usize,
        field_three: usize,
    };
    const s: S = .{ .field_one = 1, .field_two = 2, .field_three = 3 };

    try std.testing.expect(get_field_value(s, "field_two").Int == 2);
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

    var template = try initText(std.testing.allocator, templ);
    defer template.deinit();

    var buff = std.ArrayList(u8).init(std.testing.allocator);
    defer buff.deinit();

    try template.render(buff.writer(), data);

    std.testing.expect(buff.items.len == 16) catch {
        std.testing.log_level = .debug;
        std.log.debug("rendered: {s}\n  len: {}, expected 16.\n", .{
            buff.items,
            buff.items.len,
        });
        return error.WrongRenderLength;
    };
}
