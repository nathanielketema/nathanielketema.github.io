const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Html = @This();

arena: Allocator,
handle: Io.Writer.Allocating,
writer: *Io.Writer,

pub fn create(arena: Allocator) Allocator.Error!*Html {
    var html = try arena.create(Html);
    html.* = .{
        .arena = arena,
        .handle = .init(arena),
        .writer = undefined,
    };
    html.writer = &html.handle.writer;
    return html;
}

pub fn write(html: *Html, comptime template: []const u8, replacement: anytype) !void {
    const ReplacementType = @TypeOf(replacement);
    const replacement_type_info = @typeInfo(ReplacementType);
    if (replacement_type_info != .@"struct") @compileError("expected struct");

    try html.writer.print(template, replacement);
}

pub fn string(html: *Html) []const u8 {
    return html.handle.written();
}

test {
    var arena_instance: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const html = try Html.create(arena);
    const template = comptime
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

    try html.write(template, .{
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
    assert(html.string().len > template.len);
    // std.debug.print("{s}", .{html.string()});
}
