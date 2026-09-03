const std = @import("std");
const builtin = @import("builtin");
fn androidNdkTargetName(
    arch: std.Target.Cpu.Arch,
) []const u8 {
    return switch (arch) {
        .aarch64 => "aarch64-linux-android",
        .arm, .thumb => "arm-linux-androidabi",
        .x86 => "i686-linux-android",
        .x86_64 => "x86_64-linux-android",
        else => @panic("Unsupported Android architecture"),
    };
}
fn androidNdkHostTag() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "windows-x86_64",

        .linux => "linux-x86_64",

        .macos => "darwin-x86_64",

        else => @panic(
            "Unsupported Android NDK host",
        ),
    };
}
fn addAndroidNdkIncludes(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    ndk: []const u8,
    translate: ?*std.Build.Step.TranslateC,
    mod: ?*std.Build.Module,
) void {
    const host_tag = androidNdkHostTag();
    const sysroot = b.pathJoin(&.{
        ndk,
        "toolchains",
        "llvm",
        "prebuilt",
        host_tag,
        "sysroot",
    });
    const common_include = b.pathJoin(&.{
        sysroot,
        "usr",
        "include",
    });
    const target_include = b.pathJoin(&.{
        common_include,
        androidNdkTargetName(
            target.result.cpu.arch,
        ),
    });

    if (translate) |t| {
        t.addSystemIncludePath(.{
            .cwd_relative = common_include,
        });
        t.addSystemIncludePath(.{
            .cwd_relative = target_include,
        });
    }
    if (mod) |m| {
        m.addSystemIncludePath(.{
            .cwd_relative = common_include,
        });
        m.addSystemIncludePath(.{
            .cwd_relative = target_include,
        });
    }
}
fn configureAndroid(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    ndk: []const u8,
    mod: *std.Build.Module,
) void {
    addAndroidNdkIncludes(
        b,
        target,
        ndk,
        null,
        mod,
    );
}
fn configureWindows(
    b: *std.Build,
    mod: *std.Build.Module,
) void {
    mod.addIncludePath(
        b.path("external/WebView2/"),
    );
    mod.linkSystemLibrary(
        "ole32",
        .{ .use_pkg_config = .no },
    );
    mod.linkSystemLibrary(
        "shlwapi",
        .{ .use_pkg_config = .no },
    );
    mod.linkSystemLibrary(
        "version",
        .{ .use_pkg_config = .no },
    );
    mod.linkSystemLibrary(
        "advapi32",
        .{ .use_pkg_config = .no },
    );
    mod.linkSystemLibrary(
        "shell32",
        .{ .use_pkg_config = .no },
    );
    mod.linkSystemLibrary(
        "user32",
        .{ .use_pkg_config = .no },
    );
}
fn configureMacOS(
    mod: *std.Build.Module,
) void {
    mod.linkFramework(
        "WebKit",
        .{},
    );
}
fn configureLinux(
    mod: *std.Build.Module,
) void {
    mod.linkSystemLibrary(
        "gtk+-3.0",
        .{},
    );
    mod.linkSystemLibrary(
        "webkit2gtk-4.1",
        .{},
    );
}
fn configureFreeBSD(
    mod: *std.Build.Module,
) void {
    mod.linkSystemLibrary(
        "gtk-3",
        .{},
    );
    mod.linkSystemLibrary(
        "webkit2gtk-4.1",
        .{},
    );
}
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const webview_dep = b.dependency("webview", .{});

    const is_android = target.result.os.tag == .linux and
        target.result.abi == .android;

    const android_ndk = if (is_android)
        b.option(
            []const u8,
            "android-ndk",
            "Path to Android NDK",
        ) orelse b.graph.environ_map.get(
            "ANDROID_NDK_HOME",
        ) orelse b.graph.environ_map.get(
            "ANDROID_NDK_ROOT",
        ) orelse b.graph.environ_map.get(
            "NDK_HOME",
        ) orelse @panic(
            \\Android build requires Android NDK.
            \\
            \\Set:
            \\  ANDROID_NDK_HOME
            \\
            \\or use:
            \\  -Dandroid-ndk=C:/.../Android/Sdk/ndk/xx.x.x
        )
    else
        null;

    const generated = b.addWriteFiles();
    const c_api_header = generated.add("webview_zig_all.h",
        \\#include <webview/webview.h>
        \\#if defined(__ANDROID__)
        \\#include <webview/android.h>
        \\#endif
    );
    const translate = b.addTranslateC(.{
        .root_source_file = c_api_header,
        .target = target,
        .optimize = optimize,
    });

    translate.addIncludePath(webview_dep.path("core/include"));
    if (is_android) {
        addAndroidNdkIncludes(
            b,
            target,
            android_ndk.?,
            translate,
            null,
        );
    }
    const webview_raw = translate.createModule();

    const webview_mod = b.addModule("webview", .{
        .root_source_file = b.path("src/webview.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    webview_mod.addImport("webviewRaw", webview_raw);
    webview_mod.addIncludePath(webview_dep.path("core/include"));
    webview_mod.addCMacro("WEBVIEW_STATIC", "1");
    webview_mod.addCSourceFile(.{
        .file = webview_dep.path("core/src/webview.cc"),
        .language = .cpp,
        .flags = &.{"-std=c++17"},
    });
    //
    //
    if (is_android) {
        configureAndroid(
            b,
            target,
            android_ndk.?,
            webview_mod,
        );
    } else {
        switch (target.result.os.tag) {
            .windows => {
                configureWindows(
                    b,
                    webview_mod,
                );
            },
            .macos => {
                configureMacOS(
                    webview_mod,
                );
            },
            .linux => {
                configureLinux(
                    webview_mod,
                );
            },
            .freebsd => {
                configureFreeBSD(
                    webview_mod,
                );
            },
            else => {
                @panic(
                    "webview-zig : unsupported platform",
                );
            },
        }
    }
}
