const tasks = @import("tasks.zig");

pub const Code = enum(u8) {
    sleep = 0,
    terminateTask = 1,
    createTask = 2,
    write = 3,
    read = 4,

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

pub inline fn write(file: u32, data: []const u8) usize {
    asm volatile (
        \\MOV R4, %[fd]
        \\LDM %[data], {R5, R6}
        :
        : [fd] "r" (file),
          [data] "r" (&data),
        : .{ .r4 = true, .r5 = true, .r6 = true });
    Code.write.do();
    asm volatile ("PUSH {R4}");

    var amt: usize = undefined;
    asm volatile (
        \\POP {R4}
        \\STR R4, %[amt]
        : [amt] "=m" (amt),
    );
    return amt;
}

pub inline fn read(file: u32, data: []u8) usize {
    asm volatile (
        \\MOV R4, %[fd]
        \\LDM %[data], {R5, R6}
        :
        : [fd] "r" (file),
          [data] "r" (&data),
        : .{ .r4 = true, .r5 = true, .r6 = true });
    Code.read.do();
    asm volatile ("PUSH {R4}");

    var amt: usize = undefined;
    asm volatile (
        \\POP {R4}
        \\STR R4, %[amt]
        : [amt] "=m" (amt),
    );
    return amt;
}

var schedulerStarted = false;
pub inline fn sleep(ms: u32) void {
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

pub inline fn terminateTask() void {
    Code.terminateTask.do();
}

pub inline fn createTask(name: []const u8, entry: anytype) void {
    const ep = tasks.makeTaskEntryPoint(entry);
    asm volatile (
        \\LDM %[name], {R4, R5}
        \\MOV R6, %[entryPtr]
        :
        : [name] "r" (&name),
          [entryPtr] "r" (ep),
        : .{ .r4 = true, .r5 = true, .r6 = true });
    Code.createTask.do();
}
