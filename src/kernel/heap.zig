const std = @import("std");

const GPA = std.heap.DebugAllocator(.{
    .never_unmap = true,
    .backing_allocator_zeroes = false,
    .safety = false, // I'd like to enable this, but I can't :(
    // Make page size quite low, default of 128KiB is way too high
    //  considering we only have 512KiB minus .data and .bss!
    .page_size = 8 * 1024,
});

// These are initialized in the init function below. They cannot be initialized at comptime
//  because we don't know where the kernel's heap begins, or how big it is until after linking.
var gpaBackingAllocators: [2]std.heap.FixedBufferAllocator = undefined;
var gpaBacking: std.heap.FixedBufferAllocator = undefined;

var gpa: GPA = undefined;

fn allocBelongsTo(mem: []u8, alloc: *std.heap.FixedBufferAllocator) bool {
    return (@intFromPtr(mem.ptr) >= @intFromPtr(alloc.buffer.ptr) and @intFromPtr(mem.ptr) + mem.len < @intFromPtr(alloc.buffer.ptr) + alloc.buffer.len);
}

fn gpaBackingAllocate(_: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    for (&gpaBackingAllocators) |*alloc| {
        if (alloc.allocator().vtable.alloc(alloc, len, alignment, ret_addr)) |val| return val;
    }
    return null;
}

fn gpaBackingFree(_: *anyopaque, data: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    for (&gpaBackingAllocators) |*alloc| {
        if (allocBelongsTo(data, alloc)) {
            alloc.allocator().vtable.free(alloc, data, alignment, ret_addr);
        }
    }
}

fn gpaBackingRemap(_: *anyopaque, data: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    for (&gpaBackingAllocators) |*alloc| {
        if (allocBelongsTo(data, alloc)) {
            return alloc.allocator().vtable.remap(alloc, data, alignment, new_len, ret_addr);
        }
    }
    return null;
}

fn gpaBackingResize(_: *anyopaque, data: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    for (&gpaBackingAllocators) |*alloc| {
        if (allocBelongsTo(data, alloc)) {
            return alloc.allocator().vtable.resize(alloc, data, alignment, new_len, ret_addr);
        }
    }
    return false;
}

const gpaBackingAllocatorVTable = std.mem.Allocator.VTable{
    .alloc = gpaBackingAllocate,
    .free = gpaBackingFree,
    .remap = gpaBackingRemap,
    .resize = gpaBackingResize,
};

const gpaBackingAllocator: std.mem.Allocator = .{
    .ptr = @ptrFromInt(0x5A5A5A5A),
    .vtable = &gpaBackingAllocatorVTable,
};

pub fn allocator() std.mem.Allocator {
    return gpa.allocator();
}

pub fn init() !void {
    const dtcmHeapBase = @intFromPtr(@extern(?*usize, .{ .name = "__dtcm_heap_begin" }).?);
    const dtcmHeapSize = @intFromPtr(@extern(?*usize, .{ .name = "__dtcm_heap_size" }).?);
    const ocmHeapBase = @intFromPtr(@extern(?*usize, .{ .name = "__ocm_heap_begin" }).?);
    const ocmHeapSize = @intFromPtr(@extern(?*usize, .{ .name = "__ocm_heap_size" }).?);

    gpaBackingAllocators[0] = std.heap.FixedBufferAllocator.init(@as([*]u8, @ptrFromInt(dtcmHeapBase))[0..dtcmHeapSize]);
    gpaBackingAllocators[1] = std.heap.FixedBufferAllocator.init(@as([*]u8, @ptrFromInt(ocmHeapBase))[0..ocmHeapSize]);

    gpa = .{ .backing_allocator = gpaBackingAllocator };
}
