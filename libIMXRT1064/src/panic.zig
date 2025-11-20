pub const panic = std.debug.FullPanic(panicEnd);

const std = @import("std");
const debug = @import("m7/debug.zig");
const gpio = @import("gpio.zig");
const lpuart = @import("lpuart.zig");

// TODO: Let this flash by using systick waits. Also, we'd like to define which gpio bus they are on.
// If these are set, then the panic handler will set the RED led on.
pub var redLEDPin: ?u5 = null;
pub var greenLEDPin: ?u5 = null;
pub var blueLEDPin: ?u5 = null;

var panicBuffer: [4096]u8 = undefined;
fn panicEnd(msg: []const u8, faultAddr: ?usize) noreturn {
    asm volatile ("CPSID i");

    var writer = lpuart.lpuart1.writer();

    writer.print("\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n", .{}) catch @breakpoint();
    if (faultAddr) |faddr| {
        writer.print("Panic! At the 0x{x}\n{s}\n\n", .{ faddr, msg }) catch @breakpoint();
    } else {
        writer.print("Panic!\n{s}\n\n", .{msg}) catch @breakpoint();
    }

    writer.print("I'm not moving another inch!!!", .{}) catch @breakpoint();

    if (debug.coreDebug.haltingControlAndStatusRegister.haltingDebugEnable) {
        while (true) {
            @breakpoint();
        }
    } else {
        if (redLEDPin) |red| {
            gpio.gpio2.pinWrite(red, true);
        }
        if (greenLEDPin) |green| {
            gpio.gpio2.pinWrite(green, false);
        }
        if (blueLEDPin) |blue| {
            gpio.gpio2.pinWrite(blue, false);
        }
        while (true) {}
    }
}
