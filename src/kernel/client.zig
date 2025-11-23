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
    allocateMemory = 5,
    freeMemory = 6,

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
    var amt: usize = undefined;

    if (data.len == 0) return 0;
    asm volatile (
        \\MOV R4, %[fd]
        \\LDM %[data], {R5, R6}
        :
        : [fd] "r" (file),
          [data] "r" (&data),
        : .{ .r4 = true, .r5 = true, .r6 = true });
    Code.write.do();
    asm volatile (
        \\STR R4, %[amt]
        : [amt] "=m" (amt),
        :
        : .{ .r4 = true });
    return amt;
}

pub inline fn read(file: u32, data: []u8) usize {
    var amt: usize = undefined;

    if (data.len == 0) return 0;
    asm volatile (
        \\MOV R4, %[fd]
        \\LDM %[data], {R5, R6}
        :
        : [fd] "r" (file),
          [data] "r" (&data),
        : .{ .r4 = true, .r5 = true, .r6 = true });
    Code.read.do();
    asm volatile (
        \\STR R4, %[amt]
        : [amt] "=m" (amt),
        :
        : .{ .r4 = true });
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

pub const AllocationError = error{
    OutOfMemory,
    RequestedSizeNotAMultipleOfPageSize,
};

// Returns a u8 slice of at least numBytes, or an error.
pub inline fn allocateMemory(numBytes: usize) AllocationError![]u8 {
    var er: u32 = undefined;
    var ret: u32 = undefined;
    var retlen: u32 = undefined;

    asm volatile (
        \\MOV R4, %[sz]
        :
        : [sz] "r" (numBytes),
        : .{ .r4 = true });
    Code.allocateMemory.do();
    asm volatile (
        \\STR R4, %[er]
        \\STR R5, %[ret]
        \\STR R6, %[retlen]
        : [er] "=m" (er),
          [ret] "=m" (ret),
          [retlen] "=m" (retlen),
        :
        : .{ .r4 = true, .r5 = true, .r6 = true });
    if (er == 1) {
        return error.OutOfMemory;
    } else if (er == 2) {
        return error.RequestedSizeNotAMultipleOfPageSize;
    }
    return @as([*]u8, @ptrFromInt(ret))[0..retlen];
}

pub inline fn freeMemory(mem: []u8) void {
    asm volatile (
        \\MOV R4, %[ptr]
        \\MOV R5, %[length]
        :
        : [ptr] "r" (mem.ptr),
          [length] "r" (mem.len),
        : .{ .r4 = true });
    Code.freeMemory.do();
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

fn kernelAlloc(_: *anyopaque, len: usize, _: std.mem.Alignment, _: usize) ?[*]u8 {
    const realLen = (len + 4095) & ~@as(usize, 4095);
    const sl = allocateMemory(realLen) catch return null;
    return sl.ptr;
}

fn kernelFree(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
    freeMemory(memory);
}

fn kernelRemap(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) ?[*]u8 {
    // This is grossly inefficient -
    if (new_len & ~@as(u32, 4095) != new_len) return null;
    const newMem = allocateMemory(new_len) catch return null;
    @memcpy(newMem, memory);
    freeMemory(memory);
    return newMem.ptr;
}

fn kernelResize(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
    const mptr = @intFromPtr(memory.ptr);
    // If the requested memory block end is in the same 4KiB region as the current end, then no new allocation is needed; we already have the memory.
    // If not, then we can't resize it, sorry.
    // A little todo here would be to get a way of requesting the kernel to _see_ if we can allocate right next to here, essentially, pass the
    //  resize request through to the allocator in the kernel itself.
    return (((mptr + memory.len) & ~@as(usize, 4095)) == ((mptr + new_len) & ~@as(usize, 4095)));
}

const kernelAllocatorVTable = std.mem.Allocator.VTable{
    .alloc = kernelAlloc,
    .free = kernelFree,
    .remap = kernelRemap,
    .resize = kernelResize,
};

pub fn kernelAllocator() std.mem.Allocator {
    return std.mem.Allocator{
        .ptr = @ptrFromInt(0x5A5A5A5A),
        .vtable = &kernelAllocatorVTable,
    };
}

pub const DebugAllocator = std.heap.DebugAllocator(.{
    .never_unmap = false,
    .backing_allocator_zeroes = true,
    .safety = false, // Can't enable this in client just yet.
    // May want to adjust - allocations bigger or equal to this size will cause a mapping.
    //  Obviously, if I allocate 4097 bytes, having 8192 bytes dedicated to that allocation is a bit of a waste!
    .page_size = 4096,
    .enable_memory_limit = true, // I only set this so I can see the memory usage...
});

pub fn debugAllocator() DebugAllocator {
    return DebugAllocator{ .backing_allocator = kernelAllocator(), .requested_memory_limit = 0xFFFFFFFF };
}
