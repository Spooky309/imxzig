const std = @import("std");
const libIMXRT1064 = @import("libIMXRT1064");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const mxrtDep = b.dependency("libIMXRT1064", .{
        .optimize = optimize,
        .imageBase = 0x70000000,
        .imageSize = 0x400000,
    });

    const mxrtModule = mxrtDep.module("libIMXRT1064");

    const exeModule = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = mxrtModule.resolved_target,
        .optimize = optimize,
        .unwind_tables = .none,
        .single_threaded = true,
    });

    exeModule.addImport("libIMXRT1064", mxrtModule);

    const exe = b.addExecutable(.{
        .name = "imxzig.axf",
        .root_module = exeModule,
        .use_llvm = true,
        .use_lld = true,
    });

    // Make sure we run the step that generates the linker script!
    exe.step.dependOn(&mxrtDep.namedWriteFiles("linkScript").step);

    exe.setLinkerScript(mxrtDep.namedLazyPath("linkScript"));
    exe.link_function_sections = true;
    exe.link_data_sections = true;
    exe.link_gc_sections = true;

    b.installArtifact(exe);

    const bin = b.addObjCopy(exe.getEmittedBin(), .{
        .format = .bin,
    });
    const install_bin = b.addInstallBinFile(bin.getOutput(), "./imxzig.bin");
    install_bin.step.dependOn(&bin.step);
    b.getInstallStep().dependOn(&install_bin.step);
}
