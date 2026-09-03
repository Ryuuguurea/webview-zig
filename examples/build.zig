const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
fn addExample(
    b: *std.Build,
    name: []const u8,
    webview_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const app_mod = b.createModule(.{ .root_source_file = b.path(
        b.fmt("{s}.zig", .{name}),
    ), .target = target, .optimize = optimize });
    app_mod.addImport(
        "webview",
        webview_mod,
    );
    const app = b.addExecutable(.{
        .name = name,
        .root_module = app_mod,
    });
    const run = b.addRunArtifact(app);
    const step = b.step(name, b.fmt("run {s}", .{name}));
    step.dependOn(&run.step);
}
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const webview_dep = b.dependency("webview", .{
        .target = target,
        .optimize = optimize,
    });
    const is_android = target.result.os.tag == .linux and target.result.abi == .android;

    if (is_android) {
        const android_mod = b.createModule(.{
            .root_source_file = b.path(
                "android.zig",
            ),
            .target = target,
            .optimize = optimize,
            .pic = true,
        });
        android_mod.addImport(
            "webview",
            webview_dep.module("webview"),
        );
        const android = b.addLibrary(.{
            .name = "android",
            .root_module = android_mod,
            .linkage = .dynamic,
        });
        const android_step = b.step("android", "check android compiler");
        android_step.dependOn(&android.step);
    } else {
        addExample(
            b,
            "basic",
            webview_dep.module("webview"),
            target,
            optimize,
        );
        addExample(
            b,
            "bind",
            webview_dep.module("webview"),
            target,
            optimize,
        );
        addExample(
            b,
            "dispatch",
            webview_dep.module("webview"),
            target,
            optimize,
        );
        addExample(
            b,
            "eval",
            webview_dep.module("webview"),
            target,
            optimize,
        );
    }
    //

}
