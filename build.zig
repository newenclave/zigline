const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("zigline", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const unit_tests = b.addModule("tests", .{
        .root_source_file = b.path("tests/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zigline",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "zigline",
                    .module = mod,
                },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = unit_tests,
    });

    mod_tests.root_module.addImport("zigline", mod);

    const test_filter = b.option([]const u8, "test-filter", "Filter tests by name");
    if (test_filter) |filter| {
        const owned = b.allocator.dupe(u8, filter) catch @panic("OOM duping test-filter");

        const filters = b.allocator.alloc([]const u8, 1) catch @panic("OOM alloc filters");
        filters[0] = owned;

        mod_tests.filters = filters;
    }

    const install_tests = b.addInstallArtifact(mod_tests, .{});

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    const install_test_step = b.step("install-tests", "Install test executable for debugging");
    install_test_step.dependOn(&install_tests.step);
}
