const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const Template = @import("Template.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const site_url = "https://nathanielketema.github.io/";
const template_entry = @embedFile("templates/entry.xml");
const template_feed = @embedFile("templates/feed.xml");

pub fn main(init: std.process.Init) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const cwd = Io.Dir.cwd();

    var args = init.minimal.args.iterate();
    _ = args.skip(); // skip exe
    const path_output = args.next().?;

    var entries = Template.create(arena) catch oom();
    while (args.next()) |arg| {
        const title = arg;
        const date = args.next().?;
        const page_url = args.next().?;
        const description = args.next().?;
        const content = cwd.readFileAlloc(io, args.next().?, arena, .unlimited) catch |err|
            fatal("unable to read file: {t}\n", .{err});

        entries.write(template_entry, .{
            .title = title,
            .date = date,
            .page_url = page_url,
            .description = description,
            .content = content,
            .site_url = site_url,
            .page_url_stem = page_url[0 .. page_url.len - 5], // trim ".html"
        }) catch |err| fatal("unable to write rss entry to template: {t}\n", .{err});
    }

    var feed = Template.create(arena) catch oom();
    feed.write(template_feed, .{
        .date = utc(io, arena),
        .site_url = site_url,
        .entries = entries.string(),
    }) catch |err| fatal("unable to write rss feed to template: {t}\n", .{err});

    Io.Dir.writeFile(.cwd(), io, .{
        .sub_path = path_output,
        .data = feed.string(),
    }) catch |err| fatal("unable to write file: {t}\n", .{err});
}

fn utc(io: Io, arena: Allocator) []u8 {
    errdefer |err| fatal("failed to get UTC timestamp: {t}\n", .{err});

    const timestamp = Io.Timestamp.now(io, .real);
    const seconds = timestamp.toSeconds();
    const epoch_seconds = std.time.epoch.EpochSeconds{
        .secs = @intCast(seconds),
    };

    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    const milliseconds: u16 = @intCast(@divTrunc(
        @rem(timestamp.toNanoseconds(), std.time.ns_per_s),
        std.time.ns_per_ms,
    ));
    const result = try std.fmt.allocPrint(
        arena,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z",
        .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
            milliseconds,
        },
    );

    return result;
}

fn oom() noreturn {
    fatal("oom\n", .{});
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}
