const std = @import("std");

pub fn build(b: *std.Build) !void {
    const model = std.Target.arm.cpu.cortex_m7;

    const target = b.resolveTargetQuery(.{
        .abi = .eabihf,
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .ofmt = .elf,
        .cpu_model = .{ .explicit = &model },
        .cpu_features_add = std.Target.arm.featureSet(&.{
            .fp_armv8d16,
        }),
    });

    const rootMod = b.addModule("libIMXRT1064", .{
        .root_source_file = b.path("src/imxrt1064.zig"),
        .target = target,
        .link_libc = false,
        .link_libcpp = false,
        .single_threaded = true,
        .pic = false,
        .stack_check = false,
        .stack_protector = false,
        .no_builtin = false,
        .optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode") orelse b.standardOptimizeOption(.{}),
        .unwind_tables = .none,
    });

    const itcmBase = b.option(usize, "itcmBase", "Base address of ITCM") orelse 0x10000;
    const itcmSize = b.option(usize, "itcmSize", "Size of ITCM") orelse 0x40000;
    const dtcmBase = b.option(usize, "dtcmBase", "Base address of DTCM") orelse 0x20000000;
    const dtcmSize = b.option(usize, "dtcmSize", "Size of DTCM") orelse 0x40000;
    const ocmBase = b.option(usize, "ocmBase", "Base address of OCM") orelse 0x20200000;
    const ocmSize = b.option(usize, "ocmSize", "Size of OCM") orelse 0x80000;
    const imageBase = b.option(usize, "imageBase", "Base address image will execute from.") orelse 0x70000000;
    const imageSize = b.option(usize, "imageSize", "Size of the image in flash.") orelse 0x400000;
    const sdramBase = b.option(usize, "sdramBase", "Base address of SDRAM") orelse 0x80000000;
    const sdramSize = b.option(usize, "sdramSize", "Size of SDRAM") orelse 0x1e00000;
    const ncacheBase = b.option(usize, "ncacheBase", "Base address of NCACHE") orelse 0x81e00000;
    const ncacheSize = b.option(usize, "ncacheSize", "Size of NCACHE") orelse 0x200000;

    const stackSize = b.option(usize, "stackSize", "How big is the supervisor stack") orelse 0x2000;

    const opt = b.addOptions();
    opt.addOption(usize, "itcmBase", itcmBase);
    opt.addOption(usize, "itcmSize", itcmSize);
    opt.addOption(usize, "dtcmBase", dtcmBase);
    opt.addOption(usize, "dtcmSize", dtcmSize);
    opt.addOption(usize, "ocmBase", ocmBase);
    opt.addOption(usize, "ocmSize", ocmSize);
    opt.addOption(usize, "imageBase", imageBase);
    opt.addOption(usize, "imageSize", imageSize);
    opt.addOption(usize, "sdramBase", sdramBase);
    opt.addOption(usize, "sdramSize", sdramSize);
    opt.addOption(usize, "ncacheBase", ncacheBase);
    opt.addOption(usize, "ncacheSize", ncacheSize);
    opt.addOption(usize, "stackSize", stackSize);

    rootMod.addOptions("compconfig", opt);

    const writeFile = b.addNamedWriteFiles("linkScript");

    const generatedLinkerScript = try generateLinkerScript(b.allocator, .{
        .itcmBase = itcmBase,
        .itcmSize = itcmSize,
        .dtcmBase = dtcmBase,
        .dtcmSize = dtcmSize,
        .ocmBase = ocmBase,
        .ocmSize = ocmSize,
        .imageBase = imageBase,
        .imageSize = imageSize,
        .sdramBase = sdramBase,
        .sdramSize = sdramSize,
        .ncacheBase = ncacheBase,
        .ncacheSize = ncacheSize,
        .stackSize = stackSize,
    });

    b.addNamedLazyPath("linkScript", writeFile.add("link.ld", generatedLinkerScript));
}

fn generateLinkerScript(gpa: std.mem.Allocator, options: anytype) ![]u8 {
    var buf: [10]u8 = undefined;

    const template = @embedFile("src/linktemplate.ld");

    var output = try gpa.dupe(u8, template);

    const info = @typeInfo(@TypeOf(options)).@"struct";
    inline for (info.fields) |field| {
        if (field.type != usize) @compileError("Can only pass numbers in here.");

        const val = @field(options, field.name);

        var bufWriter = std.Io.Writer.fixed(&buf);
        try bufWriter.print("0x{x}", .{val});

        const outsz = std.mem.replacementSize(u8, output, field.name, buf[0..bufWriter.end]);
        const newbuf = try gpa.alloc(u8, outsz);
        _ = std.mem.replace(u8, output, field.name, buf[0..bufWriter.end], newbuf);
        output = newbuf;
    }

    return output;
}
