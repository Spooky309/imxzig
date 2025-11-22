const std = @import("std");
const imx = @import("libIMXRT1064");

const heap = @import("heap.zig");

const Pipe = @import("pipe.zig");

const Operation = struct {
    const Kind = enum {
        none,
        read,
        write,
    };

    op: union(Kind) {
        none: void,
        read: struct {
            pipe: Pipe,
            streamWriter: std.Io.Writer,
        },
        write: struct {
            pipe: Pipe,
            dataLeft: []const u8,
        },
    },
};

const TaskControlBlock = struct {
    name: []const u8,
    node: std.DoublyLinkedList.Node = .{},
    returnState: imx.interrupt.ReturnState = .{},
    stack: []u8 = &.{},
    stdio: ?Pipe = null,

    waitingOperation: Operation = .{ .op = .none },
};

pub const TaskEntryPoint = *const fn () callconv(.c) void;

const SCHEDULER_FREQUENCY_HZ = 100;
const TASK_STACK_SIZE = 8192;
var tcbPool: std.heap.MemoryPool(TaskControlBlock) = undefined;

pub var activeTcbs = std.DoublyLinkedList{};
pub var waitingTcbs = std.DoublyLinkedList{};

pub var currentTcb: *TaskControlBlock = undefined;

pub fn systickHandler(irs: imx.interrupt.ReturnState) callconv(.c) void {
    @setRuntimeSafety(false);
    currentTcb.returnState = irs;
    scheduler();
}

pub fn makeTaskEntryPoint(e: anytype) TaskEntryPoint {
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
            @import("syscallClient.zig").terminateTask();
        }
    }.entry;
}

// This should only be called from ISRs when we want to switch tasks!!!
pub fn scheduler() noreturn {
    @setRuntimeSafety(false);

    // First, handle the wait conditions on any waiting TCBs
    var waiter = waitingTcbs.first;
    while (waiter) |w| {
        var waitingTcb: *TaskControlBlock = @fieldParentPtr("node", w);
        var stopWaiting = false;
        switch (waitingTcb.waitingOperation.op) {
            .none => {
                stopWaiting = true;
            },
            .read => |*rop| {
                _ = rop.pipe.reader.stream(&rop.streamWriter, .limited(rop.streamWriter.buffer.len - rop.streamWriter.end)) catch {}; // Do something!
                if (rop.streamWriter.end == rop.streamWriter.buffer.len) {
                    stopWaiting = true;
                }
            },
            .write => |*wop| {
                const amtWritten = wop.pipe.writer.write(wop.dataLeft) catch 0; // Do something!
                wop.dataLeft = wop.dataLeft[amtWritten..][0 .. wop.dataLeft.len - amtWritten];
                if (wop.dataLeft.len == 0) {
                    stopWaiting = true;
                }
            },
        }

        const newWaiter = w.next;

        if (stopWaiting) {
            waitingTcbs.remove(w);
            activeTcbs.append(w);
        }

        waiter = newWaiter;
    }

    // Very simple round-robin.
    const tcb: *TaskControlBlock = @fieldParentPtr("node", activeTcbs.popFirst().?);
    currentTcb = tcb;
    activeTcbs.append(&tcb.node);

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
    );

    unreachable;
}

pub fn create(name: []const u8, entry: TaskEntryPoint) !void {
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
    };

    var newStack = @as(*imx.interrupt.StandardStackFrame, @ptrFromInt(newTcb.returnState.SP));

    newStack.* = .{};
    newStack.PC = @intFromPtr(entry);

    activeTcbs.append(&newTcb.node);
}

// If input is currentTcb, it will set currentTcb to the first thing in the list
pub fn destroy(tcb: *TaskControlBlock) void {
    activeTcbs.remove(&tcb.node);
    heap.allocator().free(tcb.stack);
    tcbPool.destroy(tcb);
    if (currentTcb == tcb) {
        // Initialize currentTcb to a reasonable value, so any further operations using currentTcb aren't using stale data.
        currentTcb = @fieldParentPtr("node", activeTcbs.first.?);
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

    try create("Idle", makeTaskEntryPoint(idleTask));

    currentTcb = @fieldParentPtr("node", activeTcbs.first.?);
}
