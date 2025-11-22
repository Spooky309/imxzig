const systemControlBlock = @import("systemControlBlock.zig");

pub const Error = error{
    InvalidIRQNumber,
};

pub fn enableIRQ(irqNum: u32) !void {
    if ((irqNum / 32) >= @as(u32, @intCast(systemControlBlock.interruptControlTypeRegister.lineCountDiv32MinusOne + 1))) {
        return error.InvalidIRQNumber;
    }
    irqSetEnableRegister[irqNum / 32] |= @as(u32, 1) << @intCast(irqNum % 32);
    asm volatile (
        \\DSB
        \\ISB
    );
}

pub fn disableIRQ(irqNum: u32) !void {
    if ((irqNum / 32) >= @as(u32, @intCast(systemControlBlock.interruptControlTypeRegister.lineCountDiv32MinusOne + 1))) {
        return error.InvalidIRQNumber;
    }
    irqClearEnableRegister[irqNum / 32] |= @as(u32, 1) << @intCast(irqNum % 32);
    asm volatile (
        \\DSB
        \\ISB
    );
}

const irqSetEnableRegister: *volatile [16]u32 = @ptrFromInt(0xE000E100);
const irqClearEnableRegister: *volatile [16]u32 = @ptrFromInt(0xE000E180);
const irqSetPendingRegister: *volatile [16]u32 = @ptrFromInt(0xE000E200);
const irqClearPendingRegister: *volatile [16]u32 = @ptrFromInt(0xE000E280);
const irqActiveBitRegister: *volatile [16]u32 = @ptrFromInt(0xE000E300);
const irqPriorityRegister: *volatile [124]u32 = @ptrFromInt(0xE000E400);
