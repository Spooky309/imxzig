const clockControlModule = @import("clockControlModule.zig");

pub const Direction = enum(u1) { input = 0, output = 1 };

pub const InterruptMode = enum {
    none,
    lowLevel,
    highLevel,
    risingEdge,
    fallingEdge,
    risingOrFallingEdge,
};

pub const PinConfig = struct {
    direction: Direction,
    defaultOutput: bool,
    interruptMode: InterruptMode,
};

const InternalInterruptMode = enum(u2) {
    lowLevel = 1,
    highLevel = 2,
    risingEdge = 3,
    fallingEdge = 4,
};

const GpioRegister = extern struct {
    currentData: u32,
    // You can't put an arrays in packed struct
    direction: u32,
    padStatus: u32,
    interruptConfiguration: [2]u32,
    interruptMask: u32, // 1 = enabled
    interruptStatus: u32, // 1 = triggered
    edgeSelect: u32, // 1 = interrupt on any edge
    _pad0: [100]u8 = @splat(0),
    dataSet: u32,
    dataClear: u32,
    dataToggle: u32,
};

fn GPIO(clock: ?*align(4:30:4) volatile clockControlModule.ClockGatingState, register: *volatile GpioRegister) type {
    return struct {
        pub fn pinWrite(pin: u5, val: bool) void {
            if (val) {
                register.dataSet = @as(u32, 1) << pin;
            } else {
                register.dataClear = @as(u32, 1) << pin;
            }
        }
        pub fn pinSetInterruptMode(pin: u5, mode: InterruptMode) void {
            var reg = register.*;

            if (mode == .none) {
                reg.interruptMask &= ~(@as(u32, 1) << pin);
            }
            if (mode == .lowLevel or mode == .highLevel or mode == .risingEdge or mode == .fallingEdge) {
                reg.interruptMask |= @as(u32, 1) << pin;
                reg.edgeSelect &= ~(@as(u32, 1) << pin);
                reg.interruptConfiguration[pin / 16] &= ~(@as(u32, @intFromEnum(mode)) << ((pin % 16) * 2));
            } else {
                reg.interruptMask |= @as(u32, 1) << pin;
                reg.edgeSelect |= @as(u32, 1) << pin;
            }

            register.* = reg;
        }
        pub fn pinInit(pin: u5, config: PinConfig) void {
            var reg = register.*;
            if (clock) |c| {
                c.* = .onWhileInRunOrWaitMode;
            }
            reg.interruptMask &= ~(@as(u32, 1) << pin);
            if (config.direction == .output and config.defaultOutput) {
                reg.dataSet = @as(u32, 1) << pin;
            }
            reg.direction |= @as(u32, @intFromEnum(config.direction)) << pin;
            register.* = reg;

            pinSetInterruptMode(pin, config.interruptMode);
        }
    };
}

pub const gpio1 = GPIO(&clockControlModule.ccm.gating1.gpio1, @ptrFromInt(0x401B8000));
pub const gpio2 = GPIO(&clockControlModule.ccm.gating0.gpio2, @ptrFromInt(0x401B8000 + (0x4000 * 1)));
pub const gpio3 = GPIO(&clockControlModule.ccm.gating2.gpio3, @ptrFromInt(0x401B8000 + (0x4000 * 2)));
pub const gpio4 = GPIO(&clockControlModule.ccm.gating3.gpio4, @ptrFromInt(0x401B8000 + (0x4000 * 3)));
pub const gpio5 = GPIO(&clockControlModule.ccm.gating1.gpio5, @ptrFromInt(0x400C0000));
pub const gpio6 = GPIO(null, @ptrFromInt(0x42000000));
pub const gpio7 = GPIO(null, @ptrFromInt(0x401B8000 + (0x42000000 * 1)));
pub const gpio8 = GPIO(null, @ptrFromInt(0x401B8000 + (0x42000000 * 2)));
pub const gpio9 = GPIO(null, @ptrFromInt(0x401B8000 + (0x42000000 * 3)));
pub const gpio10 = GPIO(null, @ptrFromInt(0x401B8000 + (0x42000000 * 4)));
