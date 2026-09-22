const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const mem = std.mem;
const fmt = std.fmt;
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Template = @import("Template.zig");

const Tools = enum {
    touch,
    publish,
    dev,
    spell,
};

const tools: std.StaticStringMap(Tools) = .initComptime(.{
    .{ "touch", .touch },
    .{ "publish", .publish },
    .{ "dev", .dev },
    .{ "spell", .spell },
});

const KiB = 1024;
const path_posts = "content/posts/";
const path_drafts = "content/drafts/";

const usage =
    \\Usage: zig build tools -- <tool> arg
    \\
    \\Tools:
    \\  touch       Creates new draft
    \\  publish     Stamps todays date and moves draft to posts.
    \\  dev         Serves zig-out/www/ locally.
    \\  spell       Copies a prompt for spell checking
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    var args = init.minimal.args.iterate();
    _ = args.skip(); // Skip executable

    const pick = args.next() orelse fatal("{s}\n", .{usage});
    const tool = if (tools.get(pick)) |tl| tl else fatal("{s}\n", .{usage});

    switch (tool) {
        .touch => {
            const arg = args.next() orelse fatal("{s}\n", .{usage});
            touch(io, arena, .{ .arg = arg });
        },
        .publish => {
            const arg = args.next() orelse fatal("{s}\n", .{usage});
            publish(io, arena, arg);
        },
        .spell => {
            const arg = args.next() orelse fatal("{s}\n", .{usage});
            spell(io, arena, arg);
        },
        .dev => dev(io),
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

/// Spawns `pbcopy` to copy prompt to clipboard
pub fn spell(io: Io, arena: Allocator, arg: []const u8) void {
    errdefer |err| fatal("unable to copy: {t}\n", .{err});

    var buffer: [KiB]u8 = undefined;
    const file = try Io.Dir.openFile(.cwd(), io, arg, .{});
    var file_reader = file.reader(io, &buffer);
    const reader = &file_reader.interface;

    const stat = try file.stat(io);
    const post = try reader.readAlloc(arena, stat.size);

    const content = try std.fmt.allocPrint(arena,
        \\You are a professional editor. Please identify typos and grammatical errors in the following
        \\blog post.
        \\
        \\IMPORTANT RULES:
        \\
        \\1. Find only typos and grammatical errors
        \\2. Do NOT suggest style changes or voice modifications
        \\3. Do NOT suggest adding or removing content
        \\4. For each error found, provide the exact text to replace and what to replace it with
        \\
        \\Please respond in this exact format:
        \\REPLACEMENTS_START
        \\replace "incorrect text 1" with "correct text 1"
        \\replace "incorrect text 2" with "correct text 2"
        \\REPLACEMENTS_END
        \\
        \\SUGGESTIONS_START
        \\- [optional style/clarity suggestion 1]
        \\- [optional style/clarity suggestion 2]
        \\- [optional style/clarity suggestion 3]
        \\SUGGESTIONS_END
        \\
        \\You can have as many suggestions as you want!
        \\
        \\Here is the blog post to check:
        \\{s}
        \\
    , .{post});

    var child = try std.process.spawn(io, .{
        .argv = &.{"pbcopy"},
        .stdin = .pipe,
    });

    if (child.stdin) |*stdin| {
        try stdin.writeStreamingAll(io, content);
        child.stdin.?.close(io);
        child.stdin = null;
    }

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
