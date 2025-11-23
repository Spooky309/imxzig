const std = @import("std");
const interrupt = @import("interrupt.zig");
const tasks = @import("tasks.zig");
const heap = @import("heap.zig");

const imx = @import("libIMXRT1064");

fn eeperCompareFn(_: void, a: Eeper, b: Eeper) std.math.Order {
    if (eepyTimes.items[a.timeIndex] < eepyTimes.items[b.timeIndex]) {
        return .lt;
    } else if (eepyTimes.items[a.timeIndex] > eepyTimes.items[b.timeIndex]) {
        return .gt;
    }
    return .eq;
}

const Eeper = struct {
    tcb: *tasks.TaskControlBlock,
    timeIndex: u32,
};

var eepyTimes = std.ArrayList(u32).empty;
var freeTimeSlots = std.ArrayList(u32).empty;

var eepers: std.PriorityDequeue(Eeper, void, eeperCompareFn) = undefined;

fn gpt1Handler() callconv(.c) void {
    @setRuntimeSafety(false);

    // Clear status flag or else it keeps asserting the IRQ line forever!
    imx.gpt.gpt1.status = .{};

    for (eepyTimes.items) |*time| {
        time.* -= 1; // Let it overflow unused slots I don't care.
    }
    while (eepers.peekMin()) |min| {
        if (eepyTimes.items[min.timeIndex] != 0) {
            break;
        }
        min.tcb.prod();
        freeTimeSlots.append(heap.allocator(), min.timeIndex) catch {}; // Oh dear.
        _ = eepers.removeMin();
    }

    asm volatile (
        \\DSB
        \\ISB
    );
}

pub fn addEeper(tcb: *tasks.TaskControlBlock, time: u32) !void {
    const index = blk: {
        if (freeTimeSlots.pop()) |freeSlot| {
            eepyTimes.items[freeSlot] = time;
            break :blk freeSlot;
        }
        try eepyTimes.append(heap.allocator(), time);
        break :blk eepyTimes.items.len - 1;
    };

    try eepers.add(.{ .tcb = tcb, .timeIndex = index });
}

pub fn init() !void {
    eepers = @TypeOf(eepers).init(heap.allocator(), {});

    try interrupt.registerAndEnableIRQ("GPT1", imx.interrupt.makeISR(&gpt1Handler));

    imx.clockControlModule.ccm.gating0.gpt2_bus = .onWhileInRunOrWaitMode;
    imx.clockControlModule.ccm.gating0.gpt2_serial = .onWhileInRunOrWaitMode;
    imx.clockControlModule.ccm.gating1.gpt1_bus = .onWhileInRunOrWaitMode;
    imx.clockControlModule.ccm.gating1.gpt1_serial = .onWhileInRunOrWaitMode;

    // Set up GPT1, this will be a 1MHz clock we use for process timing,
    //  It will send an interrupt every 1ms, we can use it in a REALLY lean handler
    // just to prod any processes that have active wait events.
    const gpt1 = imx.gpt.gpt1;

    // First, disable the module
    gpt1.control.enable = false;

    // Software reset
    gpt1.control.softwareReset = true;
    while (gpt1.control.softwareReset) {}

    // Change clock source
    var ctrl = gpt1.control;
    ctrl.enable24MHzInput = true;
    ctrl.clockSource = .crystalOscillator24M;
    ctrl.resetCountersOnEnable = true;
    gpt1.control = ctrl;

    // Compound division of 24, brings 24MHz to 1MHz
    gpt1.prescaler.denominatorMinusOne = 11;
    gpt1.prescaler.denominator24MMinusOne = 1;

    // 1MHz clock, compare 1000 -> 1ms tick
    gpt1.outputCompare1 = 1000;

    // Ensure that just happened before we hit the enable bit.
    asm volatile (
        \\DSB
        \\ISB
    );

    gpt1.control.enable = true;
    asm volatile (
        \\DSB
        \\ISB
    );

    // We only care about output compare 1
    gpt1.interrupt.outputCompare1InterruptEnable = true;
    asm volatile (
        \\DSB
        \\ISB
    );

    // GPT2 will be for high-precision performance timing, so we will use the 24M clock divided by 1.

    const gpt2 = imx.gpt.gpt2;
    gpt2.control.enable = false;
    gpt2.control.softwareReset = true;
    while (gpt2.control.softwareReset) {}
    ctrl = gpt2.control;
    ctrl.enable24MHzInput = true;
    ctrl.clockSource = .crystalOscillator24M;
    ctrl.resetCountersOnEnable = true;
    ctrl.behaviourOnCompareEvent = .continueToOverflow;
    gpt2.control = ctrl;
    gpt2.prescaler.denominatorMinusOne = 0;
    gpt2.prescaler.denominator24MMinusOne = 0;
    asm volatile (
        \\DSB
        \\ISB
    );
    gpt2.control.enable = true;
}
