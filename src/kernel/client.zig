const std = @import("std");
const imx = @import("libIMXRT1064");
const tasks = @import("tasks.zig");

// This file is the only file that kernel.zig makes visible to the outside world.
//  as `kernel.client`. Only client-side stuff should be in here.
// If you're looking for the handler, it's in interrupts.zig

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
    if (data.len == 0) return 0;
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
    if (data.len == 0) return 0;
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

pub inline fn sleep(ms: u32) void {
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

// Non syscall

pub inline fn readPerformanceCounter() u32 {
    return imx.gpt.gpt2.counter;
}

pub inline fn getPerformanceCounterFrequencyHz() u32 {
    // Should probably inspect gpt2 state to get the actual frequency, but for now we know what it is.
    return 24_000_000;
}

fn stdioDrain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    var numBytesWritten: usize = 0;
    _ = write(0, w.buffer[0..w.end]);
    w.end = 0;
    for (0..data.len - 1) |i| {
        _ = write(0, data[i]);
        numBytesWritten += data[i].len;
    }
    for (0..splat) |_| {
        _ = write(0, data[data.len - 1]);
        numBytesWritten += data[data.len - 1].len;
    }
    return numBytesWritten;
}

const stdioVtable = std.Io.Writer.VTable{
    .drain = stdioDrain,
};

pub fn stdioWriter() std.Io.Writer {
    return .{
        .vtable = &stdioVtable,
        .buffer = &.{},
    };
}
