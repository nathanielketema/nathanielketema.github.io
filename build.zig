const std = @import("std");

pub const extensions_exclude: []const []const u8 = &.{
    ".DS_Store",
};

pub fn build(b: *std.Build) void {
    const blog = b.addWriteFiles();

    const pandoc_bin = get_pandoc_bin(b) orelse return;
    const md_files_path = b.run(&.{ "git", "ls-files", ":(glob)content/**/*.md" });
    var md_files_path_it = std.mem.tokenizeScalar(u8, md_files_path, '\n');
    while (md_files_path_it.next()) |md_file_path| {
        const md_file_lazy_path = b.path(md_file_path);
        const html_generated_lazy_path = md_to_html(b, pandoc_bin, md_file_lazy_path);

        const html_path = blk: {
            var path = md_file_path;
            path = cut_prefix(path, "content/").?;
            path = cut_suffix(path, ".md").?;
            path = b.fmt("{s}.html", .{path});
            break :blk path; 
        };

        _ = blog.addCopyFile(html_generated_lazy_path, html_path);
    }

    b.installDirectory(.{
        .source_dir = blog.getDirectory(),
        .install_dir = .bin,
        .install_subdir = ".",
        .exclude_extensions = extensions_exclude,
    });
}

fn md_to_html(
    b: *std.Build,
    pandoc: std.Build.LazyPath,
    md_file: std.Build.LazyPath,
) std.Build.LazyPath {
    const pandoc_step = std.Build.Step.Run.create(b, "run pandoc");
    pandoc_step.addFileArg(pandoc);
    pandoc_step.addArgs(&.{ "--from=markdown", "--to=html5" });
    pandoc_step.addFileArg(md_file);
    return pandoc_step.captureStdOut(.{});
}

fn get_pandoc_bin(b: *std.Build) ?std.Build.LazyPath {
    const host = b.graph.host.result;
    const name = switch (host.os.tag) {
        .linux => switch (host.cpu.arch) {
            .aarch64 => "pandoc_linux_arm64",
            else => @panic("unsupported cpu arch"),
        },
        .macos => switch (host.cpu.arch) {
            .aarch64 => "pandoc_macos_arm64",
            else => @panic("unsupported cpu arch"),
        },
        else => @panic("unsuppored os"),
    };

    if (b.lazyDependency(name, .{})) |dep| {
        return dep.path("bin/pandoc");
    } else return null;
}

fn cut_prefix(text: []const u8, prefix: []const u8) ?[]const u8 {
    return if (std.mem.startsWith(u8, text, prefix)) text[prefix.len..] else null;
}

fn cut_suffix(text: []const u8, suffix: []const u8) ?[]const u8 {
    return if (std.mem.endsWith(u8, text, suffix))
        text[0 .. text.len - suffix.len]
    else
        null;
}
