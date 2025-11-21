const std = @import("std");
const imx = @import("libIMXRT1064");

const syscall = @import("syscall.zig");
const tasks = @import("tasks.zig");

var localVectorTable: imx.interrupt.VectorTable align(imx.interrupt.VectorTable.alignment) = undefined;

fn svcHandler(irs: imx.interrupt.ReturnState) callconv(.c) void {
    @setRuntimeSafety(false);

    var switchTasks = false;

    const stackFrame: *imx.interrupt.StandardStackFrame = @ptrFromInt(irs.SP);
    const syscallType: syscall.Code = @enumFromInt(stackFrame.R0);

    // The sleep SVC caller filters U32_MAX after it's been passed once.
    // I'm using it to say we shouldn't store the first task's (idle)
    //  return state, because we actually just came from kernel.go
    // There's a ticket to make this behaviour nicer:
    //  https://github.com/Spooky309/imxzig/issues/25
    if (!(syscallType == .sleep and irs.R4 == 0xFFFFFFFF)) {
        tasks.currentTcb.returnState = irs;
    }

    switch (syscallType) {
        .sleep => {
            switchTasks = true;
        },
        .terminateTask => {
            switchTasks = true;
            tasks.destroy(tasks.currentTcb);
        },
        .createTask => {
            const name = @as([*]const u8, @ptrFromInt(irs.R4))[0..irs.R5];
            const entry: tasks.TaskEntryPoint = @ptrFromInt(irs.R6);
            // Return error code to caller?
            tasks.create(name, entry) catch {};
        },
        .write => {
            const fd = irs.R4;
            const data = @as([*]const u8, @ptrFromInt(irs.R5))[0..irs.R6];
            tasks.currentTcb.returnState.R4 = 0;

            // stdoio
            if (fd == 0) {
                if (tasks.currentTcb.stdio != null) {
                    tasks.currentTcb.waitingOperation = .{ .op = .{ .write = .{
                        .dataLeft = data,
                        .pipe = tasks.currentTcb.stdio.?,
                    } } };
                    tasks.activeTcbs.remove(&tasks.currentTcb.node);
                    tasks.waitingTcbs.append(&tasks.currentTcb.node);
                    switchTasks = true;
                }
            }
        },
        .read => {
            const fd = irs.R4;
            const data = @as([*]u8, @ptrFromInt(irs.R5))[0..irs.R6];
            tasks.currentTcb.returnState.R4 = 0;

            // stdio
            if (fd == 0) {
                if (tasks.currentTcb.stdio != null) {
                    tasks.currentTcb.waitingOperation = .{ .op = .{ .read = .{
                        .streamWriter = std.Io.Writer.fixed(data),
                        .pipe = tasks.currentTcb.stdio.?,
                    } } };
                    tasks.activeTcbs.remove(&tasks.currentTcb.node);
                    tasks.waitingTcbs.append(&tasks.currentTcb.node);
                    switchTasks = true;
                }
            }
        },
    }

    if (switchTasks) {
        tasks.scheduler();
    }
}

fn systickHandler(irs: imx.interrupt.ReturnState) callconv(.c) void {
    @setRuntimeSafety(false);
    tasks.currentTcb.returnState = irs;
    tasks.scheduler();
}

pub fn init() void {
    localVectorTable = imx.interrupt.VTOR.*.*;
    imx.interrupt.VTOR.* = &localVectorTable;

    localVectorTable.svc = imx.interrupt.makeISR(&svcHandler);
    localVectorTable.sysTick = imx.interrupt.makeISR(&systickHandler);
}
