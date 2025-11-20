const std = @import("std");
const imx = @import("libIMXRT1064");

const InterruptReturnState = extern struct {
    R4: usize = 0,
    R5: usize = 0,
    R6: usize = 0,
    R7: usize = 0,
    R8: usize = 0,
    R9: usize = 0,
    R10: usize = 0,
    R11: usize = 0,
    SP: usize = 0,
    excReturn: usize = 0,
};

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
    returnState: InterruptReturnState = .{},
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

pub const Syscall = enum(u8) {
    yield = 0,
    terminateCurrentTask = 1,

    pub inline fn do(comptime self: @This()) void {
        // Ensure interrupts are enabled, or else SVC faults.
        asm volatile ("CPSIE i");

        // j constraint is "immediate integer between 0 and 65535"
        //  there is no constraint for 0-255, so this is all we get.
        asm volatile ("SVC %[code]"
            :
            : [code] "j" (@intFromEnum(self)),
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
            Syscall.terminateCurrentTask.do();
        }
    };
}

fn switchIntoTask(tcb: *TaskControlBlock) void {
    @setRuntimeSafety(false);
    asm volatile (
        \\LDM %[regs], {r4-r11}
        \\MSR PSP, %[sp]
        \\MOV LR, %[excReturn]
        \\BX LR
        :
        : [regs] "r" (&tcb.returnState.R4),
          [sp] "r" (tcb.returnState.SP),
          [excReturn] "r" (tcb.returnState.excReturn),
        : .{ .r0 = true });
}

pub fn svcHandler() callconv(.c) void {
    @setRuntimeSafety(false);
    var callerState: InterruptReturnState = undefined;
    var switchTasks = false;

    // Save caller state - we may have to change to another task
    asm volatile (
        \\STM %[regs], {R4-R11}
        \\MRS R0, PSP
        \\STR R0, [%[sp]]
        \\STR LR, [%[excReturn]]
        :
        : [regs] "r" (&callerState.R4),
          [sp] "r" (&callerState.SP),
          [excReturn] "r" (&callerState.excReturn),
        : .{ .r0 = true });

    // Instead of an optional, would it be better to use a self-modifying function pointer here?
    // https://github.com/Spooky309/imxzig/issues/5
    if (currentTcb) |tcb| {
        tcb.returnState = callerState;

        const stackFrame: *InterruptStackFrame = @ptrFromInt(callerState.SP);
        const syscallType: Syscall = @enumFromInt(stackFrame.R0);

        switch (syscallType) {
            .yield => {
                switchTasks = true;
            },
            .terminateCurrentTask => {
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
    }

    switchIntoTask(currentTcb.?);
}

pub fn systickHandler() callconv(.c) void {
    @setRuntimeSafety(false);
    var callerState: InterruptReturnState = undefined;

    // Save caller state - we may have to change to another task
    asm volatile (
        \\STM %[regs], {R4-R11}
        \\MRS R0, PSP
        \\STR R0, [%[sp]]
        \\STR LR, [%[excReturn]]
        :
        : [regs] "r" (&callerState.R4),
          [sp] "r" (&callerState.SP),
          [excReturn] "r" (&callerState.excReturn),
        : .{ .r0 = true });

    // If there is no currentTcb, that means the scheduler isn't started yet, so ignore, and just return.
    // Same as above: https://github.com/Spooky309/imxzig/issues/5
    if (currentTcb) |tcb| {
        tcb.returnState = callerState;

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
    Syscall.yield.do();
    unreachable;
}
