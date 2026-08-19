const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const Html = @import("Html.zig");
const Io = std.Io;

const site_url = "https://nathanielketema.github.io/";
const template_base = @embedFile("html/base.html");

pub fn main(init: std.process.Init) void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = init.minimal.args.toSlice(arena) catch |err| {
        fatal("unable to read cmdline args: {t}\n", .{err});
    };
    assert(args.len == 5);

    const title = args[1];
    const page_url = args[2];
    const path_file_source = args[3];
    const path_file_target = args[4];
    const content = Io.Dir.readFileAlloc(
        .cwd(),
        io,
        path_file_source,
        arena,
        .unlimited,
    ) catch |err| fatal("unable to read file: {t}\n", .{err});

    var html = Html.create(arena) catch oom();
    html.write(template_base, .{
        .title = title,
        .content = content,
        .page_url = page_url,
        .site_url = site_url,
    }) catch |err| fatal("unable to write to html template: {t}\n", .{err});

    Io.Dir.writeFile(.cwd(), io, .{
        .sub_path = path_file_target,
        .data = html.string(),
    }) catch |err| fatal("unable to write file: {t}\n", .{err});
}

fn oom() noreturn {
    fatal("oom\n", .{});
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}
