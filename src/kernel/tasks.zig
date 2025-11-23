const std = @import("std");
const imx = @import("libIMXRT1064");

const heap = @import("heap.zig");
const client = @import("client.zig");

pub const TaskControlBlock = struct {
    name: []const u8,
    node: std.DoublyLinkedList.Node = .{},
    returnState: imx.interrupt.ReturnState = .{},
    stack: []u8 = &.{},
    stdio: ?Pipe = null,
    prio: Priority = .mid,

    pub fn setPrio(self: *TaskControlBlock, newPrio: Priority) void {
        if (self.prio == newPrio) return;
        activeTcbs[@intFromEnum(self.prio)].remove(&self.node);
        activeTcbs[@intFromEnum(newPrio)].append(&self.node);
        self.prio = newPrio;
    }

    pub fn waitForProd(self: *TaskControlBlock) void {
        activeTcbs[@intFromEnum(self.prio)].remove(&self.node);
        waitingTcbs.append(&self.node);
    }

    pub fn prod(self: *TaskControlBlock) void {
        waitingTcbs.remove(&self.node);
        activeTcbs[@intFromEnum(self.prio)].append(&self.node);
    }
};

pub const Pipe = struct {
    const ReadFunc = *const fn (data: []u8) Error!void;
    const WriteFunc = *const fn (data: []const u8) Error!void;

    name: []const u8,
    reader: ReadFunc,
    writer: WriteFunc,

    pub const Error = error{
        AllocationError,
    };

    // StringHashMap? Need to figure out the memory usage of it first. This is fine for now.
    var globalPipes: std.ArrayList(@This()) = .empty;

    pub fn createGlobalPipe(name: []const u8, reader: ReadFunc, writer: WriteFunc) !void {
        try globalPipes.append(heap.allocator(), .{ .name = name, .reader = reader, .writer = writer });
    }

    pub fn getGlobalPipe(name: []const u8) ?@This() {
        for (globalPipes.items) |p| {
            if (std.mem.eql(u8, p.name, name)) return p;
        }
        return null;
    }
};

pub const TaskEntryPoint = *const fn () callconv(.c) void;

const SCHEDULER_FREQUENCY_HZ = 100;
const TASK_STACK_SIZE = 8192;
var tcbPool: std.heap.MemoryPool(TaskControlBlock) = undefined;

pub const Priority = enum(u8) {
    realtime = 0,
    highest = 1,
    high = 2,
    mid = 3,
    low = 4,
    lowest = 5,
};

const numPriorityLevels = @typeInfo(Priority).@"enum".fields.len;
pub var activeTcbs: [numPriorityLevels]std.DoublyLinkedList = [_]std.DoublyLinkedList{.{}} ** numPriorityLevels;
pub var waitingTcbs = std.DoublyLinkedList{};

pub var currentTcb: *TaskControlBlock = undefined;

pub fn systickHandler(irs: imx.interrupt.ReturnState) callconv(.c) *imx.interrupt.ReturnState {
    @setRuntimeSafety(false);
    currentTcb.returnState = irs;
    scheduler();
    // Will never actually reach here but we need it for the type system
    return &currentTcb.returnState;
}

pub fn makeTaskEntryPoint(e: anytype) TaskEntryPoint {
    return struct {
        const entryInfo = @typeInfo(@TypeOf(e)).@"fn";
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
                    e() catch |err| {
                        // We need a way of getting the task's name from here.
                        // Sure, we could just grab currentTcb right now, but remember,
                        //  this runs in usermode, so it shouldn't really be able to access that.
                        // Really, a pointer to information about the task should be passed in here.
                        var writer = client.stdioWriter();
                        writer.print("Task died because of: {s}\n", .{@errorName(err)}) catch {};
                    };
                },
                .void => {
                    e();
                },
                else => {
                    @compileError("Function passed into createTask should return void, or an error union with void.");
                },
            }
            client.terminateTask();
        }
    }.entry;
}

// putCurrentBack should be false when we know we don't have a value currentTcb,
//  such as `destroy` and `init` below.
fn selectCurrentTCB() void {
    // Select the first TCB in the list for each priority level from highest to lowest.
    currentTcb = blk: {
        for (0..numPriorityLevels) |i| {
            if (activeTcbs[i].popFirst()) |node| {
                break :blk @as(*TaskControlBlock, @fieldParentPtr("node", node));
            }
        }
        @panic("No tasks!");
    };

    // Put it back to the back
    activeTcbs[@intFromEnum(currentTcb.prio)].append(&currentTcb.node);
}

// This should only be called from ISRs when we want to switch tasks!!!
pub fn scheduler() noreturn {
    @setRuntimeSafety(false);

    selectCurrentTCB();

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
        : [regs] "r" (&currentTcb.returnState.R4),
          [sp] "r" (currentTcb.returnState.SP),
          [excReturn] "r" (currentTcb.returnState.excReturn),
          [kStackTop] "r" (superStack),
    );

    unreachable;
}

pub fn create(name: []const u8, entry: TaskEntryPoint, initialPrio: ?Priority) !void {
    var newTcb = try tcbPool.create();
    const stack = try heap.allocator().alignedAlloc(u8, .@"8", TASK_STACK_SIZE);
    newTcb.* = .{
        .returnState = .{
            .R7 = @intFromPtr(&stack.ptr[stack.len]),
            .SP = @intFromPtr(&stack.ptr[stack.len - @sizeOf(imx.interrupt.StandardStackFrame)]),
            .excReturn = 0xFFFFFFFD, // Thread mode with PSP stack
        },
        .stack = stack,
        .name = name,
        .stdio = Pipe.getGlobalPipe("LPUART1"),
        .prio = initialPrio orelse .mid,
    };

    var newStack = @as(*imx.interrupt.StandardStackFrame, @ptrFromInt(newTcb.returnState.SP));

    newStack.* = .{};
    newStack.PC = @intFromPtr(entry);

    activeTcbs[@intFromEnum(newTcb.prio)].append(&newTcb.node);
}

// If input is currentTcb, it will set currentTcb to the first thing in the list
pub fn destroy(tcb: *TaskControlBlock) void {
    activeTcbs[@intFromEnum(tcb.prio)].remove(&tcb.node);
    heap.allocator().free(tcb.stack);
    tcbPool.destroy(tcb);
    if (currentTcb == tcb) {
        // Initialize currentTcb to a reasonable value, so any further operations using currentTcb aren't using stale data.
        selectCurrentTCB();
    }
}

fn idleTask() void {
    while (true) {
        asm volatile ("WFI");
    }
}

pub fn init() !void {
    // Set up SysTick to our wanted scheduler frequency.
    imx.clockControlModule.ccm.lowPowerControl.mode = .runMode;
    const systickFrequency = 100000; // imxrt1064 manual says external clock source for systick is 100khz
    const wantedSystickInterruptFrequency = SCHEDULER_FREQUENCY_HZ;
    imx.systick.reloadValue.valueToLoadWhenZeroReached = systickFrequency / wantedSystickInterruptFrequency;
    imx.systick.currentValue.* = systickFrequency / wantedSystickInterruptFrequency;
    imx.systick.controlAndStatus.* = .{
        .enabled = true,
        .triggerExceptionOnCountToZero = true,
        .clockSource = .externalClock,
        .hasCountedToZeroSinceLastRead = false,
    };

    tcbPool = std.heap.MemoryPool(TaskControlBlock).init(heap.allocator());

    try create("Idle", makeTaskEntryPoint(idleTask), .lowest);

    selectCurrentTCB();
}
