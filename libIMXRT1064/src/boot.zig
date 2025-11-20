const std = @import("std");

const interrupt = @import("interrupt.zig");
const flexspi = @import("flexspi.zig");
const watchdog = @import("watchdog.zig");

const compconfig = @import("compconfig");

const cache = @import("m7/cache.zig");
const coprocessor = @import("m7/coprocessor.zig");
const systick = @import("m7/systick.zig");

const MemConfig = extern struct {
    const Version = packed struct(u32) {
        bugFix: u8,
        minor: u8,
        major: u8,
        theLetterV: u8 = 'V',
    };

    tag: u32 = 0x42464346,
    version: Version = .{
        .bugFix = 0,
        .minor = 4,
        .major = 1,
    },
    _pad0: u32 = 0,
    readSampleClkSrc: enum(u8) {
        loopbackInternally = 0,
        loopbackFromDqsPad = 1,
        loopbackFromSckPad = 2,
        externalInputFromDqsPad = 3,
    },
    csHoldTime: u8,
    csSetupTime: u8,
    columnAddresswidth: u8 = 0,
    deviceModeCfgEnable: bool = false,
    deviceModeType: enum(u8) {
        generic = 0,
        quadEnable = 1,
        spi2xpi = 2,
        xpi2spi = 3,
        spi2nocmd = 4,
        reset = 5,
    } = .generic,
    waitTimeCfgCommands: u16 = 0,
    deviceModeSeq: flexspi.LookUpTableSequence = .{},
    deviceModeArg: u32 = 0,
    configCmdEnable: bool = false,
    configModeType: [3]u8 = [_]u8{0} ** 3,
    configCmdSeqs: [3]flexspi.LookUpTableSequence = [_]flexspi.LookUpTableSequence{.{}} ** 3,
    _pad1: u32 = 0,
    configCmdArgs: [3]u32 = [_]u32{0} ** 3,
    _pad2: u32 = 0,
    controllerMiscOption: u32 = 0,
    deviceType: enum(u8) {
        serialNOR = 1,
        serialNAND = 2,
    } = .serialNOR,
    sFlashPadType: enum(u8) {
        _1Pad = 1,
        _2Pads = 2,
        _4Pads = 4,
        _8Pads = 8,
    },
    serialClkFreq: enum(u8) {
        _30MHz = 1,
        _50MHz = 2,
        _60MHz = 3,
        _75MHz = 4,
        _80MHz = 5,
        _100MHz = 6,
        _120MHz = 7,
        _133MHz = 8,
        _166MHz = 9,
    },
    lutCustomSeqEnable: bool = false,
    _pad3: [2]u32 = [_]u32{0} ** 2,
    sFlashA1Size: u32 = 0,
    sFlashA2Size: u32 = 0,
    sFlashB1Size: u32 = 0,
    sFlashB2Size: u32 = 0,
    csPadSettingOverride: u32 = 0,
    sclkPadSettingOverride: u32 = 0,
    dataPadSettingOverride: u32 = 0,
    dqsPadSettingOverride: u32 = 0,
    timeoutInMs: u32 = 0,
    commandInterval: u32 = 0,
    dataValidTime: [2]u16 = [_]u16{0} ** 2,
    busyOffset: u16 = 0,
    busybitPolarity: u16 = 0,
    lookupTable: flexspi.LookUpTable,
    lutCustomSeq: [12]flexspi.LookUpTableSequence = [_]flexspi.LookUpTableSequence{.{}} ** 12,
    _pad4: [4]u32 = [_]u32{0} ** 4,
};

const FlashConfig = extern struct {
    memConfig: MemConfig,
    pageSize: u32,
    sectorSize: u32,
    ipSerialClockFrequency: u8 = 0,
    isUniformBlockSize: bool, // Should be a u8 in an extern struct
    _pad0: [2]u8 = .{ 0, 0 },
    // I don't know what the names of these are, because the NXP file didn't tell me,
    //  but it did say what the valid values are, so I can still restrict them.
    serialNorType: enum(u8) { @"0" = 0, @"1" = 1, @"2" = 2, @"3" = 3 } = .@"0",
    needExitNoCmdMode: bool = false,
    halfClkForNonReadCmd: bool = false,
    needRestoreNoCmdMode: bool = false,
    blockSize: u32,
    _pad1: [44]u8 = [_]u8{0} ** 44,
};

const BootData = extern struct {
    bootStart: u32 = compconfig.imageBase, // Begin of the flash
    bootSize: u32 = compconfig.imageSize, // Size of the flash
    bootPlugin: u32 = 0, // 1 if this is a plugin (???)
    padding: u32 = 0xFFFFFFFF, // To make the size 16 bytes (value is because an erased flash is 0xFF).
};

const ImageVectorTable = extern struct {
    // Internal types
    const Version = packed struct(u8) {
        minor: u4,
        major: u4,
    };
    const Header = packed struct(u32) {
        tag: u8,
        size: u16,
        version: Version,
    };
    // Cortex-M7 doc says the IVT must be aligned to the number of supported interrupts times 4, rounded up to a power of two.
    //  Really what that means, is the size of the interrupt table rounded up to PoT
    pub const ivtAlign = std.math.ceilPowerOfTwoAssert(u32, @sizeOf(interrupt.VectorTable));

    // Fields
    header: Header = .{
        .tag = 0xD1,
        .size = 0x2000,
        .version = .{ .major = 4, .minor = 1 },
    },

    ivtAddress: *align(ivtAlign) const interrupt.VectorTable,
    _pad0: u32 = 0,

    dcdAddress: u32 = 0,
    bootDataAddress: *const BootData = @ptrFromInt(compconfig.imageBase + @offsetOf(BootHeader, "bootData")),
    selfAddress: *const ImageVectorTable = @ptrFromInt(compconfig.imageBase + @offsetOf(BootHeader, "imageVectorTable")),

    csfAddress: u32 = 0,
    _pad1: u32 = 0,
};

const BootHeader = extern struct {
    flashConfig: FlashConfig,
    // the image vector table needs to be at offset 0x1000 for FlexSPI NOR boot devices.
    // this will obviously cause a compile error if the size of FlashConfig exceeds 0x1000
    // we use this FF padding instead of align because we don't want to write zeroes to flash when we don't have to!
    // maybe zig has an option to use a certain byte for alignment padding?
    _pad0: [0x1000 - @sizeOf(FlashConfig)]u8 = @splat(0xFF),
    imageVectorTable: ImageVectorTable,
    bootData: BootData = .{},
};

pub const SectionTable = struct {
    const Entry = extern struct {
        loadAddr: usize, // Initial address
        addr: usize, // Destination
        size: usize, // Size of section
    };

    entries: []Entry,

    // Set up each region in memory by copying its data (or zeroing it in the case of bss)
    pub fn setupRegions(self: SectionTable) void {
        for (self.entries) |section| {
            if (section.size == 0) continue;

            const dest: []u8 = @as([*]u8, @ptrFromInt(section.addr))[0..section.size];
            if (section.loadAddr == 0 or section.loadAddr == section.addr) {
                @memset(dest, 0);
                continue;
            }

            const src: []u8 = @as([*]u8, @ptrFromInt(section.loadAddr))[0..section.size];
            @memcpy(dest, src);
        }
    }

    pub fn get() SectionTable {
        const tableBegin = @extern([*]Entry, .{ .name = "__section_table_begin" });
        const tableSize = @intFromPtr(@extern(*usize, .{ .name = "__section_table_size" })) / @sizeOf(Entry);
        return SectionTable{
            .entries = tableBegin[0..tableSize],
        };
    }
};

var sectionTable: SectionTable = undefined;

// Main entry point (after resetISR sets up the RAM for us)
fn EntryPointHolder(comptime mainFn: anytype) type {
    return struct {
        pub fn resetISR() callconv(.c) noreturn {
            @setRuntimeSafety(false);
            asm volatile ("CPSID i"); // Manual says Boot ROM disables interrupts for us, but I don't trust it.

            // Immediately disable the watchdogs
            watchdog.WDOG1.disable();
            watchdog.WDOG2.disable();
            if (!watchdog.RTWDOG.disable()) {
                // @breakpoint();
                // whinge?
            }

            // Disable systick, bootROM may have enalbed it
            systick.controlAndStatus.enabled = false;

            // Set up to use the thread mode stack while in thread mode.
            // This means that when our stack gets corrupted, it won't cause problems for interrupt handlers.
            // Also sets the supervisor stack to start at the top of DTCM.
            // Note that in the IMXZIG project, when the scheduler starts, the thread mode stack is completely discarded.
            const superStack = @intFromPtr(@extern(?*usize, .{ .name = "__supervisor_stack_top" }).?);
            asm volatile (
                \\MRS R0, MSP
                \\MSR PSP, R0
                \\MOV R0, #2
                \\MSR CONTROL, R0
                \\MSR MSP, %[supervisorStackTop]
                \\ISB
                :
                : [supervisorStackTop] "r" (superStack),
                : .{ .r0 = true });

            // Configures lower half of OCRAM as ITCM
            //  and upper half as DTCM.
            // 0x400ac044 is LPGPR17, which maps OCRAM banks to
            //  ITCM or DTCM. Each bank is two bits.
            //  0 = off, 1 = OCRAM, 2 = DTCM, 3 = ITCM
            asm volatile (
                \\LDR R0, =0x400ac044       // IOMUXC_GPR17 address, it contains the FlexRAM bank config
                \\LDR R1, =0xaaaaffff       // See above for rationale here
                \\STR R1, [R0]              // Chuck it back in
                \\LDR R0, =0x400ac040       // IOMUXC_GPR16
                \\LDR R1, [R0]              // Load IOMUXC_GPR16
                \\ORR R1, R1, #4            // Third bit tells it to use the bank config we just wrote instead of efuses
                \\ORR R1, R1, #2            // Second bit enables DTCM
                \\ORR R1, R1, #1            // First bit enables ITCM
                \\STR R1, [R0]              // Write
                \\LDR R0, =0x400ac038       // IOMUXC_GPR14
                \\LDR R1, =0x990000         // More configuration, the two nibbles set here are setting the sizes of ITCM and DTCM.
                \\STR R1, [R0]              // Write
                \\DSB                       // Barriers to ensure all the stuff we just did sticks.
                \\ISB
                ::: .{ .r0 = true, .r1 = true });

            // Copy/zero-out sections of RAM we're going to use
            SectionTable.get().setupRegions();

            // Read the boot header so we can find the interrupt vector table
            const bootHeader: *const BootHeader = @ptrFromInt(compconfig.imageBase);

            // Set VTOR pointer to our IVT
            const VTOR: **align(ImageVectorTable.ivtAlign) const interrupt.VectorTable = @ptrFromInt(0xE000ED08);
            VTOR.* = bootHeader.imageVectorTable.ivtAddress;

            // Enable the FPU
            coprocessor.coprocessorAccessControlRegister.ctrl = .fullAccess;

            // Boot ROM may have enabled the systick, so disable it
            systick.controlAndStatus.enabled = false;

            // Enable caches
            // cache.enableDCache();
            cache.enableICache();

            mainFn() catch |e| {
                asm volatile ("CPSID i");
                var errorTraceBuffer: [512]u8 = undefined;
                var writer = std.Io.Writer.fixed(&errorTraceBuffer);
                const stackTrace = @errorReturnTrace();
                const errorName = @errorName(e);
                // If we fail to write, then do an early panic using what we have so far in the buffer.
                writer.print("Unhandled error: {s}\nError trace:", .{errorName}) catch @panic(errorTraceBuffer[0..writer.end]);
                if (stackTrace) |t| {
                    for (t.instruction_addresses[0..t.index], 0..) |iaddr, i| {
                        writer.print("\n\t{}:\t0x{x}", .{ i, iaddr }) catch @panic(errorTraceBuffer[0..writer.end]);
                    }
                }
                @panic(errorTraceBuffer[0..writer.end]);
            };
            asm volatile ("CPSID i");
            @panic("main returned");
        }
    };
}

pub fn Config(comptime mainFnType: type) type {
    return struct {
        flashConfig: FlashConfig,
        mainFn: mainFnType,
        interruptVectorTable: interrupt.VectorTable,
    };
}

fn fixupIVTEntryPointIfNecessary(comptime config: anytype) interrupt.VectorTable {
    var i = config.interruptVectorTable;
    if (i.reset == null) {
        i.reset = &EntryPointHolder(config.mainFn).resetISR;
    }
    return i;
}

pub fn generateHeader(comptime config: anytype) void {
    const ivt: interrupt.VectorTable align(ImageVectorTable.ivtAlign) = fixupIVTEntryPointIfNecessary(config.bootConfig);

    // Create the boot header.
    const bootHeader: BootHeader = .{
        .flashConfig = config.bootConfig.flashConfig,
        .imageVectorTable = .{
            .ivtAddress = &ivt,
        },
    };

    // Export that boot header we just made, we need the linker script to place it
    //  at the beginning of the image.
    @export(&bootHeader, .{ .section = ".boot_hdr", .name = "bootHeader" });
}

// Keep the linker happy (we don't use entry point.)
export fn _start() void {}
