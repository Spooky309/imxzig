const std = @import("std");
const imx = @import("libIMXRT1064");

pub const client = @import("client.zig");

// These shouldn't be public, unprivileged tasks should have to request via SVC.
const heap = @import("heap.zig");
const interrupt = @import("interrupt.zig");
const tasks = @import("tasks.zig");
const modules = @import("modules.zig");
const timers = @import("timers.zig");

pub fn go(initTask: anytype) !noreturn {
    asm volatile ("CPSID i");
    try heap.init();

    // Init interrupts BEFORE modules!!!
    interrupt.init();

    try timers.init();

    // Run modules init functions here so they can register IRQs/hooks!
    // Comptime iteration of decls in modules.zig - gives us the imports (they are structs)
    inline for (@typeInfo(modules).@"struct".decls) |decl| {
        // Grab the module decl
        const module = @field(modules, decl.name);
        // Check the return type of module.init - if it's an error union, use try, else just call it.
        if (@typeInfo(@typeInfo(@TypeOf(module.init)).@"fn".return_type.?) == .error_union) {
            try module.init();
        } else {
            module.init();
        }
    }

    try tasks.init();
    try tasks.create("Init", tasks.makeTaskEntryPoint(initTask), .highest);

    client.sleep(0);
    unreachable;
}
