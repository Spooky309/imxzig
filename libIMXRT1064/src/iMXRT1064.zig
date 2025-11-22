// Make the compconfig accessible
pub const compconfig = @import("compconfig");

pub const iomuxc = @import("iomuxc.zig");
pub const flexspi = @import("flexspi.zig");
pub const panic = @import("panic.zig");
pub const clockControlModule = @import("clockControlModule.zig");
pub const gpio = @import("gpio.zig");
pub const lpuart = @import("lpuart.zig");
pub const interrupt = @import("interrupt.zig");
pub const watchdog = @import("watchdog.zig");
pub const dma = @import("dma.zig");

pub const nvic = @import("m7/nvic.zig");

// M7 stuff
pub const systick = @import("m7/systick.zig");
pub const systemControlBlock = @import("m7/systemControlBlock.zig");

pub const boot = @import("boot.zig");

pub fn Config(mainFnType: type) type {
    return struct {
        bootConfig: boot.Config(mainFnType),
    };
}

pub fn generate(comptime config: anytype) void {
    boot.generateHeader(config);
}
