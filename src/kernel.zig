const std = @import("std");
const imx = @import("libIMXRT1064");

const interrupt = imx.interrupt;

const InterruptStackFrame = extern struct {
    R0: usize = 0,
    R1: usize = 0,
    R2: usize = 0,
    R3: usize = 0,
    R12: usize = 0,
    LR: usize = 0xDEADBEEF,
    PC: usize = 0,
    XPSR: usize = 0x01000000,
};

const TaskControlBlock = struct {
    node: std.DoublyLinkedList.Node = .{},
    returnState: interrupt.ReturnState = .{},
    stack: []u8 = &.{},
};

const TASK_STACK_SIZE = 1024;

var tcbPool: std.heap.MemoryPool(TaskControlBlock) = undefined;

var activeTcbs = std.DoublyLinkedList{};
var currentTcb: ?*TaskControlBlock = undefined;

const GPA = std.heap.DebugAllocator(.{
    .never_unmap = true,
    .backing_allocator_zeroes = false,
    .safety = false, // I'd like to enable this, but I can't :(
    // Make page size quite low, default of 128KiB is way too high
    //  considering we only have 512KiB minus .data and .bss!
    .page_size = 16 * 1024,
});

// These are initialized in the init function below
var gpaBacking: std.heap.FixedBufferAllocator = undefined;
var gpa: GPA = undefined;

pub const Syscall = struct {
    pub const Code = enum(u8) {
        sleep = 0,
        terminateTask = 1,
    };

    pub fn sleep(ms: u32) void {
        asm volatile ("MOV R4, %[ms]"
            :
            : [ms] "r" (ms),
            : .{ .r4 = true });
        do(Code.sleep);
    }

    pub fn terminateTask() void {
        do(Code.terminateTask);
    }

    inline fn do(comptime code: Code) void {
        // Ensure interrupts are enabled, or else SVC faults.
        asm volatile ("CPSIE i");

        // j constraint is "immediate integer between 0 and 65535"
        //  there is no constraint for 0-255, so this is all we get.
        asm volatile ("SVC %[code]"
            :
            : [code] "j" (@intFromEnum(code)),
        );
    }
};

fn TaskEntryPoint(e: anytype) type {
    return struct {
        const entryInfo = @typeInfo(@TypeOf(e)).@"fn";

        // Should we allow functions passed in here to
        pub fn entry() callconv(.c) void {
            asm volatile ("CPSIE i");
            if (entryInfo.params.len != 0) {
                @compileError("createTask doesn't support arguments... yet.");
            }
            switch (@typeInfo(entryInfo.return_type.?)) {
                .error_union => |t| {
                    if (t.payload != void) {
                        @compileError("Function passed into createTask should return void, or an error union with void.");
                    }
                    e() catch {
                        // Print error?
                    };
                },
                .void => {
                    e();
                },
                else => {
                    @compileError("Function passed into createTask should return void, or an error union with void.");
                },
            }
            Syscall.terminateTask();
        }
    };
}

fn switchIntoTask(tcb: *TaskControlBlock) void {
    @setRuntimeSafety(false);
    // We want to reset MSP to the top of the supervisor stack, otherwise, it never gets changed and every time
    //  this function gets called it climbs a bit lower, until it starts corrupting the heap.
    const superStack = @intFromPtr(@extern(?*usize, .{ .name = "__supervisor_stack_top" }).?);
    asm volatile (
        \\LDM %[regs], {r4-r11}
        \\MSR PSP, %[sp]
        \\MOV LR, %[excReturn]
        \\MOV SP, %[kStackTop]
        \\BX LR
        :
        : [regs] "r" (&tcb.returnState.R4),
          [sp] "r" (tcb.returnState.SP),
          [excReturn] "r" (tcb.returnState.excReturn),
          [kStackTop] "r" (superStack),
        : .{ .r0 = true });
}

pub fn svcHandler(irs: interrupt.ReturnState) callconv(.c) void {
    @setRuntimeSafety(false);
    var switchTasks = false;

    // Instead of an optional, would it be better to use a self-modifying function pointer here?
    // https://github.com/Spooky309/imxzig/issues/5
    if (currentTcb) |tcb| {
        tcb.returnState = irs;

        const stackFrame: *InterruptStackFrame = @ptrFromInt(irs.SP);
        const syscallType: Syscall.Code = @enumFromInt(stackFrame.R0);

        switch (syscallType) {
            .sleep => {
                switchTasks = true;
            },
            .terminateTask => {
                switchTasks = true;
                activeTcbs.remove(&tcb.node);
                gpa.allocator().free(tcb.stack);
                tcbPool.destroy(tcb);
            },
        }
    } else {
        switchTasks = true;
    }

    if (switchTasks) {
        currentTcb = @fieldParentPtr("node", activeTcbs.popFirst().?);
        activeTcbs.append(&currentTcb.?.node);
        switchIntoTask(currentTcb.?);
    }
}

pub fn systickHandler(irs: interrupt.ReturnState) callconv(.c) void {
    @setRuntimeSafety(false);

    // If there is no currentTcb, that means the scheduler isn't started yet, so ignore, and just return.
    // Same as above: https://github.com/Spooky309/imxzig/issues/5
    if (currentTcb) |tcb| {
        tcb.returnState = irs;

        currentTcb = @fieldParentPtr("node", activeTcbs.popFirst().?);
        activeTcbs.append(&currentTcb.?.node);

        switchIntoTask(currentTcb.?);
    }
}

pub fn init() !void {
    const kernelHeapBase = @intFromPtr(@extern(?*usize, .{ .name = "__dtcm_heap_begin" }).?);
    const kernelHeapSize = @intFromPtr(@extern(?*usize, .{ .name = "__dtcm_heap_size" }).?);

    gpaBacking = std.heap.FixedBufferAllocator.init(@as([*]u8, @ptrFromInt(kernelHeapBase))[0..kernelHeapSize]);
    gpa = .{ .backing_allocator = gpaBacking.allocator() };

    tcbPool = std.heap.MemoryPool(TaskControlBlock).init(gpa.allocator());
}

pub fn createTask(entry: anytype) !void {
    var newTcb = try tcbPool.create();
    const stack = try gpa.allocator().alignedAlloc(u8, .@"8", TASK_STACK_SIZE);
    newTcb.* = .{
        .returnState = .{
            .R7 = @intFromPtr(&stack.ptr[stack.len]),
            .SP = @intFromPtr(&stack.ptr[stack.len - @sizeOf(InterruptStackFrame)]),
            .excReturn = 0xFFFFFFFD, // Thread mode with PSP stack
        },
        .stack = stack,
    };

    var newStack = @as(*InterruptStackFrame, @ptrFromInt(newTcb.returnState.SP));

    newStack.* = .{};
    newStack.PC = @intFromPtr(&TaskEntryPoint(entry).entry);

    activeTcbs.append(&newTcb.node);
}

fn idleTask() void {
    while (true) {
        asm volatile ("WFI");
    }
}

pub fn go() !noreturn {
    try createTask(idleTask);
    // SVC handler will set things up for us on its initial entry.
    Syscall.sleep(0);
    unreachable;
}
