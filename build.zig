const std = @import("std");
const Website = @import("src/website.zig").Website;

pub fn build(b: *std.Build) void {
    const pandoc = get_pandoc_bin(b) orelse return;
    const website = Website.init(b, pandoc);
    website.build();

    const content_install = b.addInstallDirectory(.{
        .source_dir = website.content.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = "www",
        .exclude_extensions = &.{".DS_Store"},
    });
    b.getInstallStep().dependOn(&content_install.step);

    const tools_exe = b.addExecutable(.{
        .name = "tools",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools.zig"),
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
        }),
    });
    b.installArtifact(tools_exe);

    const tools_step = b.step("tools", "Tools to make life easier.");

    const tools_cmd = b.addRunArtifact(tools_exe);
    if (b.args) |args| tools_cmd.addArgs(args);
    tools_step.dependOn(&tools_cmd.step);
    tools_cmd.step.dependOn(b.getInstallStep());
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
