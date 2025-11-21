pub const std_options = std.Options{
    .allow_stack_tracing = false,
    .enable_segfault_handler = false,
    .page_size_min = 4096,
    .page_size_max = 4096,
    .queryPageSize = queryPageSize,
    .logFn = logFn,
};

fn logFn(comptime lvl: std.log.Level, comptime scope: @Type(.enum_literal), comptime msg: []const u8, args: anytype) void {
    _ = lvl;
    _ = scope;
    _ = msg;
    _ = args;
}

// We don't have paging. I'm setting it to 4096 because DebugAllocator makes assumptions about this.
fn queryPageSize() usize {
    return 4096;
}

const std = @import("std");
const imx = @import("libIMXRT1064");

const terminal = @import("terminal.zig");
const winbond_lut = @import("winbond_lut.zig");
const kernel = @import("kernel.zig");

// These need to exist. Annoying, but deal with it.
pub const panic = imx.panic.panic;

fn nullAllocator() std.mem.Allocator {
    return .{ .ptr = undefined, .vtable = undefined };
}

pub const os = struct {
    pub const heap = struct {
        // NEVER USE THIS! This is just to stop it from defaulting fields to POSIX page allocator
        //  DebugAllocator should have its .backing_allocator explicitly set to something else.
        pub const page_allocator = nullAllocator();
    };
};

comptime {
    const Config = imx.Config(@TypeOf(main));
    imx.generate(Config{
        .bootConfig = .{
            .flashConfig = .{
                .memConfig = .{
                    .readSampleClkSrc = .loopbackFromDqsPad,
                    .csHoldTime = 3,
                    .csSetupTime = 3,
                    .sFlashPadType = ._4Pads,
                    .serialClkFreq = ._100MHz,
                    .sFlashA1Size = 4 * 1024 * 1024,
                    .lookupTable = winbond_lut.get(),
                },
                .pageSize = 256,
                .sectorSize = 4 * 1024,
                .blockSize = 64 * 1024,
                .isUniformBlockSize = false,
            },
            .mainFn = main,
            .interruptVectorTable = imx.interrupt.makeIVT(.{}),
        },
    });
}

const redPin = 9;
const greenPin = 10;
const bluePin = 11;

fn initLED() void {
    imx.iomuxc.GPR.GPR27 = 0; // Set all bits to GPIO2

    // Configure the B0_xx pins as GPIO outputs.
    imx.iomuxc.swMuxPadGpio.B0.@"09" = .{ .muxMode = .gpio2_io09, .softwareInputOn = .inputPathDeterminedByFunctionality };
    imx.iomuxc.swMuxPadGpio.B0.@"10" = .{ .muxMode = .gpio2_io10, .softwareInputOn = .inputPathDeterminedByFunctionality };
    imx.iomuxc.swMuxPadGpio.B0.@"11" = .{ .muxMode = .gpio2_io11, .softwareInputOn = .inputPathDeterminedByFunctionality };

    const ledPadConfig = imx.iomuxc.SW_PAD_CTL_PAD_GPIO_REGISTER{
        .useFastSlewRate = false,
        .driveStrength = .r0_divided_6,
        .speed = .fast_150mhz,
        .openDrainEnabled = false,
        .pullKeeperEnabled = true,
        .pullKeepSelect = .keeper,
        .pullUpDown = .pull_down_100k_ohm,
        .hysteresisEnabled = false,
    };

    imx.iomuxc.swPadCtlPadGpio.B0[redPin] = ledPadConfig;
    imx.iomuxc.swPadCtlPadGpio.B0[greenPin] = ledPadConfig;
    imx.iomuxc.swPadCtlPadGpio.B0[bluePin] = ledPadConfig;

    const pinConfig = imx.gpio.PinConfig{ .direction = .output, .defaultOutput = false, .interruptMode = .none };

    imx.gpio.gpio2.pinInit(redPin, pinConfig);
    imx.gpio.gpio2.pinInit(greenPin, pinConfig);

    imx.gpio.gpio2.pinInit(bluePin, pinConfig);

    // Let panic handler get at our pins so it can make it red
    imx.panic.redLEDPin = redPin;
    imx.panic.greenLEDPin = greenPin;
    imx.panic.blueLEDPin = bluePin;
}

fn init() !void {
    _ = kernel.syscall.write(0,
        \\
        \\----------------------------------
        \\IMXZIG
        \\----------------------------------
        \\
    );

    kernel.syscall.createTask("Terminal", terminal.task);
}

fn main() !void {
    // initLED();
    // Turn on some LEDs to let us know we're loading
    // imx.gpio.gpio2.pinWrite(redPin, true);
    // imx.gpio.gpio2.pinWrite(greenPin, true);
    // imx.gpio.gpio2.pinWrite(bluePin, true);

    // Turn off the LEDs
    // imx.gpio.gpio2.pinWrite(redPin, false);
    // imx.gpio.gpio2.pinWrite(bluePin, false);
    // imx.gpio.gpio2.pinWrite(greenPin, false);

    try kernel.go(init);
}
