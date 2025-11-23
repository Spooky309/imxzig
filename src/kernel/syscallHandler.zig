const std = @import("std");
const imx = @import("libIMXRT1064");

const tasks = @import("tasks.zig");
const timers = @import("timers.zig");

const SyscallCode = @import("client.zig").Code;

pub fn svcHandler(irs: imx.interrupt.ReturnState) callconv(.c) void {
    @setRuntimeSafety(false);

    var switchTasks = false;

    const stackFrame: *imx.interrupt.StandardStackFrame = @ptrFromInt(irs.SP);
    const syscallType: SyscallCode = @enumFromInt(stackFrame.R0);

    tasks.currentTcb.returnState = irs;

    switch (syscallType) {
        .sleep => {
            const time = irs.R4;
            if (time != 0) {
                tasks.currentTcb.waitForProd();
                // Add +1 to time, because if the clock is _about_ to tick, it will go off right away.
                //  We want to guarantee that the wait lasts AT LEAST as long as the time asked for.
                // Report failure?
                timers.addEeper(tasks.currentTcb, if (time == 0xFFFFFFFF) time else time + 1) catch {
                    tasks.currentTcb.prod();
                };
            }
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
            tasks.create(name, entry, null) catch {};
        },
        .write => {
            const fd = irs.R4;
            const data = @as([*]const u8, @ptrFromInt(irs.R5))[0..irs.R6];
            tasks.currentTcb.returnState.R4 = 0;

            // stdoio
            if (fd == 0) {
                if (tasks.currentTcb.stdio) |stdio| {
                    tasks.currentTcb.waitForProd();
                    // Return error code to caller?
                    stdio.writer(data) catch {
                        tasks.currentTcb.prod();
                    };
                    switchTasks = true;
                }
            }
        },
        .read => {
            const fd = irs.R4;
            const data = @as([*]u8, @ptrFromInt(irs.R5))[0..irs.R6];
            tasks.currentTcb.returnState.R4 = 0;

            // stdoio
            if (fd == 0) {
                if (tasks.currentTcb.stdio) |stdio| {
                    tasks.currentTcb.waitForProd();
                    // Return error code to caller?
                    stdio.reader(data) catch {
                        tasks.currentTcb.prod();
                    };
                    switchTasks = true;
                }
            }
        },
    }

    if (switchTasks) {
        tasks.scheduler();
    }
}
