const std = @import("std");
const imx = @import("libIMXRT1064");

const syscallHandler = @import("syscallHandler.zig");
const tasks = @import("tasks.zig");

pub const Error = error{
    IRQAlreadyUsed,
};

var localVectorTable: imx.interrupt.VectorTable align(imx.interrupt.VectorTable.alignment) = undefined;

// Stub handler for systick so it does nothing until we're ready.
fn systickHandlerStub() callconv(.c) void {}
// Stub handler for SVC, kernel.go goes here, and it sets to the _real_ handlers, and schedules our first task
fn svcHandlerSetupStub() callconv(.c) void {
    @atomicStore(imx.interrupt.InterruptHandler, &localVectorTable.svc, imx.interrupt.makeISR(&syscallHandler.svcHandler), .seq_cst);
    @atomicStore(imx.interrupt.InterruptHandler, &localVectorTable.sysTick, imx.interrupt.makeISR(&tasks.systickHandler), .seq_cst);
    tasks.scheduler();
}

pub fn registerAndEnableIRQ(comptime name: []const u8, handler: imx.interrupt.InterruptHandler) void {
    @field(localVectorTable, name) = handler;
    const num = localVectorTable.getIrqNum(name);
    imx.nvic.enableIRQ(num);
}

pub fn init() void {
    localVectorTable = imx.interrupt.VTOR.*.*;
    imx.interrupt.VTOR.* = &localVectorTable;

    @atomicStore(imx.interrupt.InterruptHandler, &localVectorTable.svc, imx.interrupt.makeISR(&svcHandlerSetupStub), .seq_cst);
    @atomicStore(imx.interrupt.InterruptHandler, &localVectorTable.sysTick, imx.interrupt.makeISR(&systickHandlerStub), .seq_cst);
}
