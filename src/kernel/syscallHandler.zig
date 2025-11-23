const std = @import("std");
const imx = @import("libIMXRT1064");

const tasks = @import("tasks.zig");
const timers = @import("timers.zig");
const heap = @import("heap.zig");

const SyscallCode = @import("client.zig").Code;

pub fn svcHandler(irs: imx.interrupt.ReturnState) callconv(.c) *imx.interrupt.ReturnState {
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
        .allocateMemory => {
            const amt = irs.R4;
            var err: u32 = 0;
            if (amt & ~@as(u32, 4095) != amt) {
                err = 2;
            } else {
                const ret = heap.allocator().alignedAlloc(u8, .fromByteUnits(4096), amt) catch blk: {
                    err = 1;
                    break :blk @as([*]u8, @ptrFromInt(0x5A5A5A5A))[0..amt];
                };
                @memset(ret, 0);
                tasks.currentTcb.returnState.R5 = @intFromPtr(ret.ptr);
                tasks.currentTcb.returnState.R6 = ret.len;
            }
            tasks.currentTcb.returnState.R4 = err;
        },
        .freeMemory => {
            const ptr = irs.R4;
            const len = irs.R5;
            const slice = @as([*]u8, @ptrFromInt(ptr))[0..len];
            heap.allocator().free(slice);
        },
    }

    if (switchTasks) {
        tasks.scheduler();
    }

    return &tasks.currentTcb.returnState;
}
