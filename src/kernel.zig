const std = @import("std");
const imx = @import("libIMXRT1064");

pub const syscall = @import("kernel/syscall.zig");

// These shouldn't be public, unprivileged tasks should have to request via SVC.
const heap = @import("kernel/heap.zig");
const interrupt = @import("kernel/interrupt.zig");
const tasks = @import("kernel/tasks.zig");

pub fn go(initTask: anytype) !noreturn {
    asm volatile ("CPSID i");

    try heap.init();
    try tasks.init();
    interrupt.init();

    // Run modules init functions here so they can register IRQs/hooks!

    try tasks.create("Init", tasks.makeTaskEntryPoint(initTask));
    syscall.sleep(0xFFFFFFFF);
    unreachable;
}
