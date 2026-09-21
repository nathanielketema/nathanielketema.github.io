const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const Template = @import("Template.zig");
const Io = std.Io;

const site_url = "https://nathanielketema.github.io/";
const template_base = @embedFile("templates/base.html");

pub fn main(init: std.process.Init) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const cwd = Io.Dir.cwd();

    const args = init.minimal.args.toSlice(arena) catch |err| {
        fatal("unable to read cmdline args: {t}\n", .{err});
    };
    assert(args.len == 7);

    const title = args[1];
    const page_url = args[2];
    const description = args[3];
    const file_md = args[4];
    const path_file_source = args[5];
    const path_file_target = args[6];
    const content = cwd.readFileAlloc(io, path_file_source, arena, .unlimited) catch |err|
        fatal("unable to read file: {t}\n", .{err});

    var template = Template.create(arena) catch oom();
    template.write(template_base, .{
        .title = title,
        .content = content,
        .page_url = page_url,
        .site_url = site_url,
        .description = description,
        .file_md = file_md,
    }) catch |err| fatal("unable to write to html template: {t}\n", .{err});

    Io.Dir.writeFile(.cwd(), io, .{
        .sub_path = path_file_target,
        .data = template.string(),
    }) catch |err| fatal("unable to write file: {t}\n", .{err});
}

fn oom() noreturn {
    fatal("oom\n", .{});
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}
