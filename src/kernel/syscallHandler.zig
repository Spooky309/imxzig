const std = @import("std");
const imx = @import("libIMXRT1064");

const tasks = @import("tasks.zig");

const SyscallCode = @import("syscallClient.zig").Code;

pub fn svcHandler(irs: imx.interrupt.ReturnState) callconv(.c) void {
    @setRuntimeSafety(false);

    var switchTasks = false;

    const stackFrame: *imx.interrupt.StandardStackFrame = @ptrFromInt(irs.SP);
    const syscallType: SyscallCode = @enumFromInt(stackFrame.R0);

    tasks.currentTcb.returnState = irs;

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
