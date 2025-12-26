const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target and optimize options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create library module for C API (includes regex)
    const c_api_module = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create library module for main (for compatibility)
    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // =============================================================================
    // Library Compilation
    // =============================================================================

    // Shared library (.so, .dylib, .dll)
    const shared_lib = b.addLibrary(.{
        .name = "zregexp",
        .root_module = c_api_module,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .linkage = .dynamic,
    });
    b.installArtifact(shared_lib);

    // Static library (.a)
    const static_lib = b.addLibrary(.{
        .name = "zregexp",
        .root_module = c_api_module,
        .linkage = .static,
    });
    b.installArtifact(static_lib);

    // Install headers
    const install_headers = b.addInstallHeaderFile(
        b.path("include/zregexp.h"),
        "zregexp.h",
    );
    const install_headers_cpp = b.addInstallHeaderFile(
        b.path("include/zregexp.hpp"),
        "zregexp.hpp",
    );

    // Default build step (builds all libraries and installs headers)
    b.getInstallStep().dependOn(&install_headers.step);
    b.getInstallStep().dependOn(&install_headers_cpp.step);

    // =============================================================================
    // Testing
    // =============================================================================

    // Create unit test executable
    const tests = b.addTest(.{
        .root_module = lib_module,
    });

    const run_tests = b.addRunArtifact(tests);

    // Create integration test executable
    const integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_module.addImport("zregexp", lib_module);

    const integration_tests = b.addTest(.{
        .root_module = integration_module,
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);

    // Test step (runs all tests)
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    // Individual test steps
    const unit_test_step = b.step("test-unit", "Run unit tests only");
    unit_test_step.dependOn(&run_tests.step);

    const integration_test_step = b.step("test-integration", "Run integration tests only");
    integration_test_step.dependOn(&run_integration_tests.step);

    // =============================================================================
    // Library-specific build steps
    // =============================================================================

    const lib_step = b.step("lib", "Build all libraries");
    lib_step.dependOn(&static_lib.step);
    lib_step.dependOn(&shared_lib.step);
    lib_step.dependOn(&install_headers.step);
    lib_step.dependOn(&install_headers_cpp.step);

    const static_step = b.step("static", "Build static library only");
    static_step.dependOn(&static_lib.step);

    const shared_step = b.step("shared", "Build shared library only");
    shared_step.dependOn(&shared_lib.step);
}
