const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const snap = @import("Snapshot.zig").snap;

const Template = @This();

arena: Allocator,
handle: Io.Writer.Allocating,
writer: *Io.Writer,

pub fn create(arena: Allocator) Allocator.Error!*Template {
    var template = try arena.create(Template);
    template.* = .{
        .arena = arena,
        .handle = .init(arena),
        .writer = undefined,
    };
    template.writer = &template.handle.writer;
    return template;
}

pub fn write(template: *Template, comptime template_text: []const u8, replacement: anytype) !void {
    const ReplacementType = @TypeOf(replacement);
    const replacement_type_info = @typeInfo(ReplacementType);
    if (replacement_type_info != .@"struct") @compileError("expected struct");

    try template.writer.print(template_text, replacement);
}

pub fn string(template: *Template) []const u8 {
    return template.handle.written();
}

test {
    var arena_instance: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const template = try Template.create(arena);
    const template_text = comptime
        \\<!DOCTYPE html>
        \\<html lang="en-US">
        \\    <head>
        \\        <title>{[title]s}</title>
        \\        <meta name="description" content="{[description]s}">
        \\    </head>
        \\    <body>
        \\        <main>
        \\            {[children]s}
        \\        </main>
        \\    </body>
        \\</html>
    ;

    try template.write(template_text, .{
        .title = "title: test 123",
        .description = "this is a description",
        .children =
        \\<ul>
        \\  <li>1</li>
        \\  <li>2</li>
        \\  <li>3</li>
        \\</ul>
        ,
    });

    try snap(@src(),
        \\<!DOCTYPE html>
        \\<html lang="en-US">
        \\    <head>
        \\        <title>title: test 123</title>
        \\        <meta name="description" content="this is a description">
        \\    </head>
        \\    <body>
        \\        <main>
        \\            <ul>
        \\  <li>1</li>
        \\  <li>2</li>
        \\  <li>3</li>
        \\</ul>
        \\        </main>
        \\    </body>
        \\</html>
    ).diff(template.string());
}
