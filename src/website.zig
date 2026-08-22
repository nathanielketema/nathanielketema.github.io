const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const mem = std.mem;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Build = std.Build;

const Html = @import("Html.zig");

const path_base = "content/";
const path_posts = "posts/";
const say_my_name = "nathanielketema";

pub const Website = struct {
    b: *Build,
    pandoc: Build.LazyPath,
    content: *Build.Step.WriteFile,
    page_writer_exe: *Build.Step.Compile,

    pub fn init(b: *Build, pandoc: Build.LazyPath) Website {
        return .{
            .b = b,
            .pandoc = pandoc,
            .content = b.addWriteFiles(),
            .page_writer_exe = b.addExecutable(.{
                .name = "page_writer",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/page_writer.zig"),
                    .target = b.graph.host,
                }),
            }),
        };
    }

    pub fn build(website: Website) void {
        website.add_static_pages();
        website.add_posts();
        website.add_assets_and_css();
    }

    pub fn add_static_pages(website: Website) void {
        const b = website.b;
        const arena = b.allocator;

        const files_static: []const []const u8 = &.{ "index.md", "resume.md" };
        for (files_static) |file_static| {
            const source = b.path(path_base).path(b, file_static);
            const content = website.run_pandoc(source);
            const file_html = mem.concat(arena, u8, &.{
                Io.Dir.path.stem(file_static),
                ".html",
            }) catch oom();
            const page_static_out = website.write_page(.{
                .page_title = say_my_name,
                .page_url = file_html, // {site_url}/{page_url}
                .page_content = content,
            });
            _ = website.content.addCopyFile(page_static_out, file_html);
        }
    }

    pub fn add_posts(website: Website) void {
        const b = website.b;
        const arena = b.allocator;

        var html = Html.create(arena) catch oom();
        html.write("<ul>\n", .{}) catch |err| fatal_template(err);
        const posts = website.collect_posts();
        for (posts) |post| {
            html.write(
                \\<li>
                \\  <time datetime="{[time_machine]s}">{[time_human]s}</time>
                \\  <h2>
                \\     <a href="{[url]s}">{[title]s}</a>
                \\  </h2>
                \\</li>
                \\
            , .{
                .url = post.url,
                .title = post.title,
                .time_machine = post.time_machine,
                .time_human = post.time_human,
            }) catch |err| fatal_template(err);

            const page_post_out = website.write_page(.{
                .page_title = post.title,
                .page_url = b.pathJoin(&.{ path_posts, post.url }),
                .page_content = post.content,
                .page_description = post.description,
            });
            _ = website.content.addCopyFile(page_post_out, post.path_out);
        }
        html.write("</ul>\n", .{}) catch |err| fatal_template(err);

        const file_posts_index = b.addWriteFiles();
        const content_index = file_posts_index.add("posts_index.html", html.string());

        const page_posts_index_out = website.write_page(.{
            .page_title = say_my_name,
            .page_url = path_posts,
            .page_content = content_index,
        });
        _ = website.content.addCopyFile(page_posts_index_out, b.pathJoin(&.{
            path_posts,
            "index.html",
        }));
    }

    pub fn collect_posts(website: Website) []Post {
        const b = website.b;
        const io = b.graph.io;
        const arena = b.allocator;

        var dir = b.build_root.handle.openDir(io, path_base, .{ .iterate = true }) catch |err| {
            fatal_dir(err);
        };
        defer dir.close(io);

        var walker = dir.walk(arena) catch oom();
        defer walker.deinit();

        var posts = std.ArrayList(Post).initCapacity(arena, 20) catch oom();
        while (walker.next(io) catch |err| fatal_walk(err)) |entry| {
            if (entry.kind == .file) {
                if (mem.startsWith(u8, entry.path, "assets/")) continue;
                if (mem.startsWith(u8, entry.path, "css/")) continue;
                if (mem.eql(u8, entry.basename, ".DS_Store")) continue;
                if (mem.eql(u8, entry.basename, "index.md")) continue;
                if (mem.eql(u8, entry.basename, "resume.md")) continue;

                const post = Post.parse(
                    website,
                    entry.basename,
                    b.pathJoin(&.{ path_base, entry.path }),
                ) catch |err| {
                    fatal("unable to parse post {s}: {t}\n", .{ entry.path, err });
                };
                posts.append(arena, post) catch oom();
            }
        }

        mem.sort(Post, posts.items, {}, struct {
            fn greater_than(_: void, lhs: Post, rhs: Post) bool {
                if (lhs.date.year != rhs.date.year) return lhs.date.year > rhs.date.year;
                if (lhs.date.month != rhs.date.month) return lhs.date.month > rhs.date.month;
                return lhs.date.day > rhs.date.day;
            }
        }.greater_than);

        return posts.items;
    }

    pub fn add_assets_and_css(website: Website) void {
        const b = website.b;
        const io = b.graph.io;
        const arena = b.allocator;

        var dir = b.build_root.handle.openDir(io, path_base, .{ .iterate = true }) catch |err| {
            fatal_dir(err);
        };
        defer dir.close(io);

        var walker = dir.walk(arena) catch oom();
        defer walker.deinit();

        while (walker.next(io) catch |err| fatal_walk(err)) |entry| {
            if (entry.kind == .file) {
                if (mem.eql(u8, entry.basename, ".DS_Store")) continue;
                if (mem.startsWith(u8, entry.path, "posts/")) continue;
                if (mem.eql(u8, entry.basename, "index.md")) continue;
                if (mem.eql(u8, entry.basename, "resume.md")) continue;
                const source = b.path(path_base).path(b, entry.path);
                _ = website.content.addCopyFile(source, entry.path);
            }
        }
    }

    pub fn write_page(
        website: Website,
        options: struct {
            page_title: []const u8,
            page_url: []const u8,
            page_content: Build.LazyPath,
            page_description: []const u8 = "Nathaniel Ketema's personal website",
        },
    ) Build.LazyPath {
        const b = website.page_writer_exe.step.owner;

        const page_writer_run = b.addRunArtifact(website.page_writer_exe);
        page_writer_run.addArgs(&.{
            options.page_title,
            options.page_url,
            options.page_description,
        });
        page_writer_run.addFileArg(options.page_content);
        return page_writer_run.addOutputFileArg("page.html");
    }

    fn run_pandoc(website: Website, file_md: Build.LazyPath) Build.LazyPath {
        const b = website.b;
        const pandoc_step = std.Build.Step.Run.create(b, "run pandoc");
        pandoc_step.addFileArg(website.pandoc);
        pandoc_step.addArgs(&.{
            "--from", "gfm+smart-tex_math_dollars",
            "--to",   "html5",
        });
        pandoc_step.addFileArg(file_md);
        return pandoc_step.captureStdOut(.{});
    }
};

pub const Date = struct {
    year: u32,
    month: u8,
    day: u8,

    comptime {
        assert(@sizeOf(Date) == 8);
    }

    pub fn parse(year: []const u8, month: []const u8, day: []const u8) !Date {
        return .{
            .year = try std.fmt.parseInt(u32, year, 10),
            .month = try std.fmt.parseInt(u8, month, 10),
            .day = try std.fmt.parseInt(u8, day, 10),
        };
    }
};

pub const Post = struct {
    title: []const u8,
    description: []const u8,
    url: []const u8,
    path_out: []const u8,
    content: Build.LazyPath,
    date: Date,
    time_machine: []const u8,
    time_human: []const u8,

    pub fn parse(website: Website, file_md: []const u8, path_page: []const u8) !Post {
        const b = website.b;
        const io = b.graph.io;
        const arena = b.allocator;

        const page = Page.parse(io, arena, path_page) catch |err| {
            fatal("unable to parse page content of {s}: {t}\n", .{ path_page, err });
        };

        var it = mem.tokenizeScalar(u8, file_md, '_');
        const year = it.next() orelse return error.InvalidFileName;
        const month = it.next() orelse return error.InvalidFileName;
        const day = it.next() orelse return error.InvalidFileName;
        const title = page.title;
        const description = page.description;
        const file_html = blk: {
            const file_tmp = try mem.replaceOwned(u8, arena, it.rest(), "_", "-");
            const stem = Io.Dir.path.stem(file_tmp);
            break :blk try mem.concat(arena, u8, &.{ stem, ".html" });
        };

        const path_out = try mem.join(arena, "/", &.{
            path_posts[0 .. path_posts.len - 1], // remove "/" from the end
            year,
            month,
            day,
            file_html,
        });

        const url = try mem.join(arena, "/", &.{
            year,
            month,
            day,
            file_html,
        });

        const source = b.path(path_base).path(b, path_posts).path(b, file_md);
        const content = website.run_pandoc(source);

        const time_machine = try mem.join(arena, "-", &.{ year, month, day });
        const time_human = parse_machine_time(arena, time_machine) catch |err| {
            fatal("unable to parse time {s}: {t}\n", .{ time_machine, err });
        };
        const date = try Date.parse(year, month, day);

        return .{
            .title = title,
            .description = description,
            .url = url,
            .path_out = path_out,
            .content = content,
            .date = date,
            .time_machine = time_machine,
            .time_human = time_human,
        };
    }

    // YYYY-MM-DD
    // 2020-07-06 -> Jun 06, 2020
    fn parse_machine_time(arena: Allocator, time_machine: []const u8) ![]const u8 {
        var it = mem.tokenizeScalar(u8, time_machine, '-');
        const year = it.next().?;
        const month_number = try std.fmt.parseInt(u8, it.next().?, 10);
        const day = it.next().?;
        assert(it.next() == null);

        const months: []const []const u8 = &.{
            "Jan", "Feb", "Mar", "Apr",
            "May", "Jun", "Jul", "Aug",
            "Sep", "Oct", "Nov", "Dec",
        };
        assert(months.len == 12);
        const month_string = months[month_number - 1];

        return try mem.concat(arena, u8, &.{
            month_string,
            " ",
            day,
            ", ",
            year,
        });
    }
};

pub const Page = struct {
    title: []const u8,
    description: []const u8,

    pub fn parse(io: Io, arena: Allocator, path_file: []const u8) !Page {
        const text = try Io.Dir.readFileAlloc(.cwd(), io, path_file, arena, .unlimited);
        var line_iterator = mem.splitScalar(u8, text, '\n');
        const title_line = line_iterator.next() orelse return error.TitleInvalid;

        var title = mem.cutPrefix(u8, title_line, "# ") orelse return error.TitleInvalid;
        title = mem.trim(u8, title, "`");
        if (title.len < 3) return error.TitleInvalid;

        const new_line = line_iterator.next() orelse return error.NewlineMissingAfterTitle;
        assert(new_line.len == 0);

        var sentences: std.ArrayList([]const u8) = .empty;
        while (line_iterator.next()) |line| {
            if (line.len == 0) break;
            try sentences.append(arena, line);
        }

        return .{
            .title = try arena.dupe(u8, title),
            .description = try mem.join(arena, " ", sentences.items),
        };
    }
};

fn oom() noreturn {
    fatal("oom\n", .{});
}

fn fatal_dir(err: anyerror) noreturn {
    fatal("unable to open directory: {t}\n", .{err});
}

fn fatal_walk(err: anyerror) noreturn {
    fatal("unable to walk directory: {t}\n", .{err});
}

fn fatal_template(err: anyerror) noreturn {
    fatal("unable to write to html template: {t}\n", .{err});
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}
