const std = @import("std");
const imx = @import("libIMXRT1064");

const Registers = extern struct {
    R4: usize = 0,
    R5: usize = 0,
    R6: usize = 0,
    R7: usize = 0,
    R8: usize = 0,
    R9: usize = 0,
    R10: usize = 0,
    R11: usize = 0,
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
    regs: Registers = .{},
    SP: usize = 0,
    excReturn: usize = 0,
};

const TASK_STACK_SIZE = 1024;

var tcbPool: std.heap.MemoryPool(TaskControlBlock) = undefined;

var activeTcbs = std.DoublyLinkedList{};
var currentTcb: *TaskControlBlock = undefined;

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
        pub fn entry() callconv(.c) void {
            asm volatile ("CPSIE i");
            if (@typeInfo(@TypeOf(e)).@"fn".params.len != 0) {
                @compileError("createTask doesn't support arguments... yet.");
            }
            const rType = @typeInfo(@TypeOf(e)).@"fn".return_type.?;
            switch (@typeInfo(rType)) {
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
        : [regs] "r" (&tcb.regs),
          [sp] "r" (tcb.SP),
          [excReturn] "r" (tcb.excReturn),
        : .{ .r0 = true });
}

pub fn svcHandler() callconv(.c) void {
    @setRuntimeSafety(false);

    // Save caller state - we may have to change to another task
    asm volatile (
        \\STM %[regs], {R4-R11}
        \\MRS R0, PSP
        \\STR R0, [%[sp]]
        \\STR LR, [%[excReturn]]
        :
        : [regs] "r" (&currentTcb.regs),
          [sp] "r" (&currentTcb.SP),
          [excReturn] "r" (&currentTcb.excReturn),
        : .{ .r0 = true });

    const stackFrame: *InterruptStackFrame = @ptrFromInt(currentTcb.SP);
    const syscallType: Syscall = @enumFromInt(stackFrame.R0);

    var switchTasks = false;

    switch (syscallType) {
        .yield => {
            switchTasks = true;
        },
        .terminateCurrentTask => {
            switchTasks = true;
            activeTcbs.remove(&currentTcb.node);
            tcbPool.destroy(currentTcb);
            // TODO: Allocate the stack more effectively so we can return the stack
        },
    }

    if (switchTasks) {
        currentTcb = @fieldParentPtr("node", activeTcbs.popFirst().?);
        activeTcbs.append(&currentTcb.node);
    }

    switchIntoTask(currentTcb);
}

pub fn systickHandler() callconv(.c) void {
    // Save caller state - we may have to change to another task
    asm volatile (
        \\STM %[regs], {R4-R11}
        \\MRS R0, PSP
        \\STR R0, [%[sp]]
        \\STR LR, [%[excReturn]]
        :
        : [regs] "r" (&currentTcb.regs),
          [sp] "r" (&currentTcb.SP),
          [excReturn] "r" (&currentTcb.excReturn),
        : .{ .r0 = true });

    currentTcb = @fieldParentPtr("node", activeTcbs.popFirst().?);
    activeTcbs.append(&currentTcb.node);

    switchIntoTask(currentTcb);
}

pub fn init() !void {
    const sectionTable = imx.boot.SectionTable.get();

    var highestDTCMAddr = imx.compconfig.dtcmBase;
    var highestDTCMAddrSize: usize = 0;

    for (sectionTable.entries) |section| {
        if (section.addr >= imx.compconfig.dtcmBase and section.addr < imx.compconfig.dtcmBase + imx.compconfig.dtcmSize) {
            if (section.addr + section.size > highestDTCMAddr) {
                highestDTCMAddr = section.addr;
                highestDTCMAddrSize = section.size;
            }
        }
    }

    const SUPERVISOR_STACK_SIZE = 8192;
    const kernelHeapBase = highestDTCMAddr + highestDTCMAddrSize;
    const kernelHeapSize = (imx.compconfig.dtcmBase + imx.compconfig.dtcmSize - SUPERVISOR_STACK_SIZE) - kernelHeapBase;

    gpaBacking = std.heap.FixedBufferAllocator.init(@as([*]u8, @ptrFromInt(kernelHeapBase))[0..kernelHeapSize]);
    gpa = .{ .backing_allocator = gpaBacking.allocator() };

    tcbPool = std.heap.MemoryPool(TaskControlBlock).init(gpa.allocator());
}

pub fn createTask(entry: anytype) !void {
    var newTcb = try tcbPool.create();
    var sp = try gpa.allocator().alignedAlloc(u8, .@"8", TASK_STACK_SIZE);
    newTcb.* = .{
        .regs = .{
            .R7 = @intFromPtr(&sp.ptr[sp.len]),
        },
        .SP = @intFromPtr(&sp.ptr[sp.len]) - @sizeOf(InterruptStackFrame),
    };

    // Return into thread mode with PSP stack
    newTcb.excReturn = 0xFFFFFFFD;

    var newStack = @as(*InterruptStackFrame, @ptrFromInt(newTcb.SP));

    newStack.* = .{};
    newStack.PC = @intFromPtr(&TaskEntryPoint(entry).entry);

    activeTcbs.append(&newTcb.node);
}

// Interrupts should be disabled coming into here, we don't want systick going off while we're setting up.
pub fn go() !noreturn {
    // Create a TCB for this context, it will be the idle task.
    var tcb = try tcbPool.create();
    activeTcbs.append(&tcb.node);
    currentTcb = tcb;
    // This lets the SysTick interrupt go off, so it'll start scheduling.
    asm volatile ("CPSIE i");
    // Idle
    while (true) {
        asm volatile ("WFI");
    }
}
