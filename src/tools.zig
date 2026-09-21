const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const mem = std.mem;
const fmt = std.fmt;
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Template = @import("Template.zig");

const Tools = enum { touch, publish, dev };

const tools: std.StaticStringMap(Tools) = .initComptime(.{
    .{ "touch", .touch },
    .{ "publish", .publish },
    .{ "dev", .dev },
});

const KiB = 1024;
const mem_usage_max = 4 * KiB;
const path_posts = "content/posts/";
const path_drafts = "content/drafts/";

const usage =
    \\Usage: zig build tools -- <tool> arg
    \\
    \\Tools:
    \\  touch       Creates new draft
    \\  publish     Stamps todays date and moves draft to posts.
    \\  dev         Serves zig-out/www/ locally.
;

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.skip(); // Skip executable

    var buffer: [mem_usage_max]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buffer);
    var arena: std.heap.ArenaAllocator = .init(fba.allocator());
    defer arena.deinit();

    const pick = args.next() orelse fatal("{s}\n", .{usage});
    const tool = if (tools.get(pick)) |tl| tl else fatal("{s}\n", .{usage});

    switch (tool) {
        .touch => {
            const arg = args.next() orelse fatal("{s}\n", .{usage});
            touch(init.io, arena.allocator(), .{ .arg = arg });
        },
        .publish => {
            const arg = args.next() orelse fatal("{s}\n", .{usage});
            publish(init.io, arena.allocator(), arg);
        },
        .dev => dev(init.io),
    }
}

/// Moves file from draft -> posts
pub fn publish(io: Io, arena: Allocator, arg: []const u8) void {
    errdefer |err| fatal("unable to publish '{s}': {t}\n", .{ arg, err });

    // content/draft/arg -> content/posts/file_name
    const file_name_stamped = try stamp_date_to_file_name(io, arena, arg);
    const source = try Io.Dir.path.join(arena, &.{ path_drafts, arg });
    const target = try Io.Dir.path.join(arena, &.{ path_posts, file_name_stamped });

    try Io.Dir.copyFile(.cwd(), source, .cwd(), target, io, .{ .replace = false });
    try Io.Dir.deleteFile(.cwd(), io, source);
}

/// Creates a new draft file
pub fn touch(io: Io, arena: Allocator, options: struct {
    arg: []const u8,
    target: []const u8 = path_drafts,
    date: bool = false,
}) void {
    errdefer |err| fatal("unable to touch '{s}': {t}\n", .{ options.arg, err });

    // Write an H1 header with the file name
    const data = try fmt.allocPrint(arena, "# {s}\n", .{options.arg});

    const file_name = blk: {
        var file = try parse_file_name(arena, options.arg);
        if (options.date) file = try stamp_date_to_file_name(io, arena, file);
        break :blk file;
    };
    assert(options.arg.len < file_name.len);
    const sub_path = try Io.Dir.path.join(arena, &.{ options.target, file_name });

    std.log.info("touching {s}", .{file_name});
    try Io.Dir.writeFile(.cwd(), io, .{ .data = data, .sub_path = sub_path });
}

/// Change later, but for now it does the job.
pub fn dev(io: Io) void {
    errdefer |err| fatal("unable to serve site: {t}\n", .{err});

    var child = try std.process.spawn(io, .{
        .argv = &.{ "dx", "http-server", "zig-out/www", "-o" },
    });
    const term = try child.wait(io);
    if (term.exited != 0) return error.UnableToSpawnProcess;
}

/// Returned format example:
/// - "Foo bar Baz" -> "foo_bar_baz.md"
fn parse_file_name(arena: Allocator, file_name_raw: []const u8) ![]u8 {
    var file_name = try fmt.allocPrint(arena, "{s}.md", .{file_name_raw});
    file_name = try mem.replaceOwned(u8, arena, file_name, "-", "_");
    file_name = try mem.replaceOwned(u8, arena, file_name, " ", "_");
    file_name = try std.ascii.allocLowerString(arena, file_name);

    assert(file_name.len == file_name_raw.len + 3); // ".md" = 3
    return file_name;
}

/// Returned format example:
/// - "foo_bar_baz.md" -> "2026_09_16_foo_bar_baz.md"
fn stamp_date_to_file_name(io: Io, arena: Allocator, file_name: []const u8) ![]u8 {
    const date = try get_todays_date(io, arena);
    assert(date.len > 0);
    return fmt.allocPrint(arena, "{s}_{s}", .{ date, file_name });
}

/// Returned format example: "2026_09_16"
fn get_todays_date(io: Io, arena: Allocator) ![]u8 {
    const timestamp = Io.Timestamp.now(io, .real).toSeconds();
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };

    const day_epoch = epoch_seconds.getEpochDay();
    const day_year = day_epoch.calculateYearDay();
    const day_month = day_year.calculateMonthDay();

    const year = day_year.year;
    const month = day_month.month.numeric();
    const day = day_month.day_index;

    return fmt.allocPrint(arena, "{d:0>4}_{d:0>2}_{d:0>2}", .{ year, month, day });
}

fn fatal(comptime msg: []const u8, args: anytype) noreturn {
    std.debug.print(msg, args);
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
        \\foo_bar.md
    ).diff(try parse_file_name(arena, "foo_bar"));

    try snap(@src(),
        \\hello_world!_this_is_nice.md
    ).diff(try parse_file_name(arena, "Hello World! this is nice"));

    try snap(@src(),
        \\the_quick_brown_fox_jumps_over_the_lazy_dog.md
    ).diff(try parse_file_name(arena, "The quick brown fox jumps over the lazy dog"));

    try snap(@src(),
        \\2026_09_19
    ).diff(try get_todays_date(io, arena));

    try snap(@src(),
        \\2026_09_19_foo_bar.md
    ).diff(try stamp_date_to_file_name(io, arena, "foo_bar.md"));
}
