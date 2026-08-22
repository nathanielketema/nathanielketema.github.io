const std = @import("std");
const Website = @import("src/website.zig").Website;

pub fn build(b: *std.Build) void {
    const io = b.graph.io;

    const pandoc = get_pandoc_bin(b) orelse return;
    const website = Website.init(b, pandoc);
    website.build();
    defer std.log.info("Website built successfully!", .{});

    b.build_root.handle.deleteTree(io, "zig-out") catch |err| {
        std.debug.print("unable to delete `zig-out`: {t}\n", .{err});
        std.process.exit(1);
    };
    const content_install = b.addInstallDirectory(.{
        .source_dir = website.content.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = "www",
        .exclude_extensions = &.{".DS_Store"},
    });
    b.getInstallStep().dependOn(&content_install.step);
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
        .windows => "pandoc_windows_x86_64",
        else => @panic("unsuppored os"),
    };

    if (b.lazyDependency(name, .{})) |dep| {
        return dep.path("bin/pandoc");
    } else return null;
}
