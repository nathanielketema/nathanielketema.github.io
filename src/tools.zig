const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const mem = std.mem;
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Tools = enum { touch };

const tools: std.StaticStringMap(Tools) = .initComptime(.{
    .{ "touch", .touch },
});

const usage =
    \\Usage: zig build tools -- <tool> arg
    \\
    \\Tools:
    \\  touch       Create new Post
;

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.skip(); // Skip executable

    const pick = args.next() orelse fatal("{s}\n", .{usage});
    const tool = if (tools.get(pick)) |tl| tl else fatal("{s}\n", .{usage});
    const arg = args.next() orelse fatal("{s}\n", .{usage});

    switch (tool) {
        .touch => try touch(init.io, arg),
    }
}

// Has a system dependency on unix command line utility `date`.
pub fn touch(io: Io, arg: []const u8) !void {
    var buffer: [2 * Io.Dir.max_path_bytes]u8 = undefined; // ~8KiB
    var fba: std.heap.FixedBufferAllocator = .init(&buffer);
    const arena = fba.allocator();

    // Write an H1 header with the file name
    const data = try std.fmt.allocPrint(arena, "# {s}\n", .{arg});

    const file_name = try parse_file_name(io, arena, arg);
    assert(arg.len < file_name.len);
    const sub_path = try Io.Dir.path.join(arena, &.{ "content/posts/", file_name });

    std.log.info("touching {s}", .{file_name});
    try Io.Dir.writeFile(.cwd(), io, .{ .data = data, .sub_path = sub_path });
}

/// Turns raw file name to proper post name with format
/// `date_file_name.md`.
///
/// Eg:
///     "Foo bar Baz" -> "2026_09_16_foo_bar_baz.md"
fn parse_file_name(io: Io, arena: Allocator, file_name_raw: []const u8) ![]u8 {
    const date = try get_todays_date(io, arena);
    assert(date.len > 0);

    var file_name = try std.fmt.allocPrint(arena, "{s}_{s}.md", .{ date, file_name_raw });
    file_name = try mem.replaceOwned(u8, arena, file_name, "-", "_");
    file_name = try mem.replaceOwned(u8, arena, file_name, " ", "_");
    file_name = try std.ascii.allocLowerString(arena, file_name);

    // "_" + ".md" = 4
    assert(file_name.len == file_name_raw.len + date.len + 4);
    return file_name;
}

/// Get date from `date` program
/// - return format eg: "2026-09-16"
fn get_todays_date(io: Io, arena: Allocator) ![]u8 {
    const date = try std.process.run(arena, io, .{ .argv = &.{ "date", "+%Y-%m-%d" } });
    if (date.term.exited != 0) fatal("process 'date' failed\n{s}", .{date.stderr});

    assert(date.stdout[date.stdout.len - 1] == '\n');
    return date.stdout[0 .. date.stdout.len - 1];
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

// Test is dependent on the date it's run. For this reason the
// first run will always fail. Make sure the error is caused by
// the date and update the snapshot.
test {
    const snap = @import("Snapshot.zig").snap;
    var arena_instance: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();
    const io = testing.io;

    try snap(@src(),
        \\2026-09-17
    ).diff(try get_todays_date(io, arena));

    try snap(@src(),
        \\2026_09_17_foo_bar.md
    ).diff(try parse_file_name(io, arena, "foo_bar"));

    try snap(@src(),
        \\2026_09_17_hello_world!_this_is_nice.md
    ).diff(try parse_file_name(io, arena, "Hello World! this is nice"));

    try snap(@src(),
        \\2026_09_17_the_quick_brown_fox_jumps_over_the_lazy_dog.md
    ).diff(try parse_file_name(io, arena, "The quick brown fox jumps over the lazy dog"));
}
