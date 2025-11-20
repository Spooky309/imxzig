const std = @import("std");
const libIMXRT1064 = @import("libIMXRT1064");

pub fn build(b: *std.Build) !void {
    const useOwnObjcopy = b.option(bool, "useOwnObjcopy", "Use our own objcopy implementation instead of the one in the compiler") orelse true;
    const optimize = b.standardOptimizeOption(.{});

    const mxrtDep = b.dependency("libIMXRT1064", .{
        .optimize = optimize,
        .imageBase = 0x70000000,
        .imageSize = 0x400000,
    });

    const mxrtModule = mxrtDep.module("libIMXRT1064");

    const mainProgramModule = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = mxrtModule.resolved_target,
        .optimize = optimize,
        .unwind_tables = .none,
        .single_threaded = true,
    });

    mainProgramModule.addImport("libIMXRT1064", mxrtModule);

    const mainProgram = b.addExecutable(.{
        .name = "imxzig.axf",
        .root_module = mainProgramModule,
        .use_llvm = true,
        .use_lld = true,
    });

    // Make sure we run the step that generates the linker script!
    mainProgram.step.dependOn(&mxrtDep.namedWriteFiles("linkScript").step);

    mainProgram.setLinkerScript(mxrtDep.namedLazyPath("linkScript"));
    mainProgram.link_function_sections = true;
    mainProgram.link_data_sections = true;
    mainProgram.link_gc_sections = true;

    const bin = if (useOwnObjcopy) blk: {
        std.log.info("Using our own objcopy", .{});
        const objCopyExe = b.addExecutable(.{
            .name = "objcopy",
            .root_module = b.createModule(.{
                .root_source_file = b.path("objcopy.zig"),
                .target = b.resolveTargetQuery(.{}),
                .optimize = .ReleaseSafe,
            }),
        });
        // Build objcopy after the AXF
        objCopyExe.step.dependOn(&mainProgram.step);
        const objCopyRun = b.addRunArtifact(objCopyExe);

        objCopyRun.addArgs(&.{ "-O", "binary" });
        objCopyRun.addArtifactArg(mainProgram);
        const outLazyPath = objCopyRun.addOutputFileArg("out.bin");

        break :blk .{ &objCopyRun.step, outLazyPath };
    } else blk: {
        std.log.warn("Using Zig's objcopy. Check to see that the output isn't 2GiBs!", .{});
        const objCopyRun = b.addObjCopy(mainProgram.getEmittedBin(), .{
            .format = .bin,
        });
        break :blk .{ &objCopyRun.step, objCopyRun.getOutput() };
    };

    const install_bin = b.addInstallBinFile(bin.@"1", "./imxzig.bin");
    install_bin.step.dependOn(bin.@"0");
    b.getInstallStep().dependOn(&install_bin.step);
}
