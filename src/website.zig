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

        const posts = website.collect_posts();
        for (posts) |post| {
            const page_post_out = website.write_page(.{
                .page_title = post.title,
                .page_url = b.pathJoin(&.{ path_posts, post.url }),
                .page_content = post.content,
            });
            _ = website.content.addCopyFile(page_post_out, post.path_out);
        }

        var html = Html.create(arena) catch oom();
        const content_posts = comptime
            \\<ul>
            \\  <li>test: post</li>
            \\</ul>
        ;
        html.write(content_posts, .{}) catch |err| {
            fatal("unable to write to html template: {t}\n", .{err});
        };

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

    pub const Post = struct {
        title: []const u8,
        url: []const u8,
        path_out: []const u8,
        content: Build.LazyPath,

        pub fn parse(website: Website, file_md: []const u8) Post {
            const b = website.b;
            const arena = b.allocator;

            var it = mem.tokenizeScalar(u8, file_md, '_');
            const year = it.next().?;
            const month = it.next().?;
            const day = it.next().?;
            const title = "TODO: change me later";
            const file_html = blk: {
                const file_tmp = mem.replaceOwned(u8, arena, it.rest(), "_", "-") catch oom();
                const stem = Io.Dir.path.stem(file_tmp);
                break :blk mem.concat(arena, u8, &.{ stem, ".html" }) catch oom();
            };

            const path_out = mem.join(arena, "/", &.{
                path_posts[0 .. path_posts.len - 1], // remove "/" from the end
                year,
                month,
                day,
                file_html,
            }) catch oom();

            const url = mem.join(arena, "/", &.{
                year,
                month,
                day,
                file_html,
            }) catch oom();

            const source = b.path(path_base).path(b, path_posts).path(b, file_md);
            const content = website.run_pandoc(source);

            return .{
                .title = title,
                .url = url,
                .path_out = path_out,
                .content = content,
            };
        }
    };

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

                const post = Post.parse(website, entry.basename);
                posts.append(arena, post) catch oom();
            }
        }

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

    pub fn write_page(website: Website, options: struct {
        page_title: []const u8,
        page_url: []const u8,
        page_content: Build.LazyPath,
    }) Build.LazyPath {
        const b = website.page_writer_exe.step.owner;

        const page_writer_run = b.addRunArtifact(website.page_writer_exe);
        page_writer_run.addArgs(&.{
            options.page_title,
            options.page_url,
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

fn oom() noreturn {
    fatal("oom\n", .{});
}

fn fatal_dir(err: anyerror) noreturn {
    fatal("unable to open directory: {t}\n", .{err});
}

fn fatal_walk(err: anyerror) noreturn {
    fatal("unable to walk directory: {t}\n", .{err});
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}
