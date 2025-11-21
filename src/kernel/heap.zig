const std = @import("std");

const GPA = std.heap.DebugAllocator(.{
    .never_unmap = true,
    .backing_allocator_zeroes = false,
    .safety = false, // I'd like to enable this, but I can't :(
    // Make page size quite low, default of 128KiB is way too high
    //  considering we only have 512KiB minus .data and .bss!
    .page_size = 16 * 1024,
});

// These are initialized in the init function below. They cannot be initialized at comptime
//  because we don't know where the kernel's heap begins, or how big it is until after linking.
var gpaBacking: std.heap.FixedBufferAllocator = undefined;
var gpa: GPA = undefined;

pub fn allocator() std.mem.Allocator {
    return gpa.allocator();
}

pub fn init() !void {
    const heapBase = @intFromPtr(@extern(?*usize, .{ .name = "__dtcm_heap_begin" }).?);
    const heapSize = @intFromPtr(@extern(?*usize, .{ .name = "__dtcm_heap_size" }).?);

    gpaBacking = std.heap.FixedBufferAllocator.init(@as([*]u8, @ptrFromInt(heapBase))[0..heapSize]);
    gpa = .{ .backing_allocator = gpaBacking.allocator() };
}
