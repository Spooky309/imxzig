const tasks = @import("tasks.zig");

pub const Code = enum(u8) {
    sleep = 0,
    terminateTask = 1,
    createTask = 2,

    inline fn do(comptime self: @This()) void {
        // j constraint is "immediate integer between 0 and 65535"
        asm volatile (
            \\CPSIE i
            \\SVC %[code]
            :
            : [code] "j" (@intFromEnum(self)),
        );
    }
};

var schedulerStarted = false;
pub fn sleep(ms: u32) void {
    if (schedulerStarted and ms == 0xFFFFFFFF) {
        return;
    }
    schedulerStarted = true;

    asm volatile ("MOV R4, %[ms]"
        :
        : [ms] "r" (ms),
        : .{ .r4 = true });
    Code.sleep.do();
}

pub fn terminateTask() void {
    Code.terminateTask.do();
}

pub fn createTask(name: []const u8, entry: anytype) void {
    const ep = tasks.makeTaskEntryPoint(entry);
    asm volatile (
        \\LDM %[name], {R4, R5}
        \\MOV R6, %[entryPtr]
        :
        : [name] "r" (&name),
          [entryPtr] "r" (ep),
    );
    Code.createTask.do();
}
