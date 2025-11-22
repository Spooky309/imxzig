const std = @import("std");
const imx = @import("libIMXRT1064");

const tasks = @import("../tasks.zig");
const interrupt = @import("../interrupt.zig");
const heap = @import("../heap.zig");

const WriteOperation = struct {
    tcb: *tasks.TaskControlBlock, // TCB that inintiated and is waiting for this operation
    buf: []const u8,
};

const ReadOperation = struct {
    tcb: *tasks.TaskControlBlock, // TCB that inintiated and is waiting for this operation
    buf: []u8,
};

var writeOperations = std.Deque(WriteOperation).empty;
var readOperations = std.Deque(ReadOperation).empty;

const txChannel = imx.dma.channels[0];
const rxChannel = imx.dma.channels[16];

const OpKind = enum { read, write };

fn setOp(data: []const u8, kind: OpKind) void {
    var tcd = switch (kind) {
        .read => rxChannel.edmaTcd.*,
        .write => txChannel.edmaTcd.*,
    };

    switch (kind) {
        .read => {
            tcd.destinationAddress = @intFromPtr(data.ptr);
            tcd.destinationAddressOffset = 1;
        },
        .write => {
            tcd.sourceAddress = @intFromPtr(data.ptr);
            tcd.sourceAddressOffset = 1;
        },
    }

    tcd.minorLoopLink.disabled = .{
        .currentMajorIterationCount = @intCast(data.len),
        .enableChannelLinkOnMinorLoopComplete = false,
    };
    tcd.beginningMinorLoopLink.disabled = .{
        .enableMinorLoopLink = false,
        .startingMajorIterationCount = @intCast(data.len),
    };
    tcd.minorByteCountOrOffset = .{ .minorByteCount = 1 };
    tcd.controlAndStatus = .{
        .start = false,
        .interruptOnMajorCountComplete = true,
        .interruptOnMajorCountHalfComplete = false,
        .disableRequestOnMajorCountComplete = true,
        .enableChannelLinkOnMajorLoopComplete = false,
        .bandwidthControl = .noStall,
        .channelActive = false,
        .channelDone = false,
        .enableScatterGather = false,
        .majorLoopChannelLinkChannelNumber = 0,
        ._pad0 = 0,
    };

    switch (kind) {
        .read => rxChannel.edmaTcd.* = tcd,
        .write => txChannel.edmaTcd.* = tcd,
    }
    // A wise man once told me that if it's acting strange you should try a barrier.
    //  Seems to be helping.
    asm volatile (
        \\DSB
        \\ISB
    );

    switch (kind) {
        .read => {
            imx.dma.enableRequestRegister.* |= (@as(u32, 1) << 16);
            imx.lpuart.lpuart1.setRxDMA(true);
        },
        .write => {
            imx.dma.enableRequestRegister.* |= 1;
            imx.lpuart.lpuart1.setTxDMA(true);
        },
    }
}

fn irqHandler() callconv(.c) void {
    const reqs = imx.dma.interruptRequests.*;
    imx.dma.interruptRequests.* = 0xFFFFFFFF;

    if (imx.dma.edmaErrorStatus.anyError) {
        @panic("edma fail");
    }

    if (reqs & 1 != 0) {
        txChannel.edmaTcd.controlAndStatus.interruptOnMajorCountComplete = false;
        imx.lpuart.lpuart1.setTxDMA(false);
        imx.dma.enableRequestRegister.* &= ~@as(u32, 1);
        asm volatile (
            \\DSB
            \\ISB
        );
        const tcb = writeOperations.popFront();
        tcb.?.tcb.prod();

        if (writeOperations.front()) |newOp| {
            setOp(newOp.buf, .write);
        }
    }
    if (reqs & (@as(u32, 1) << 16) != 0) {
        rxChannel.edmaTcd.controlAndStatus.interruptOnMajorCountComplete = false;
        imx.lpuart.lpuart1.setRxDMA(false);
        imx.dma.enableRequestRegister.* &= ~(@as(u32, 1) << 16);
        asm volatile (
            \\DSB
            \\ISB
        );
        const tcb = readOperations.popFront();
        tcb.?.tcb.prod();

        if (readOperations.front()) |newOp| {
            setOp(newOp.buf, .read);
        }
    }
}

fn pipeRead(data: []u8) tasks.Pipe.Error!void {
    if (readOperations.len == 0) {
        setOp(data, .read);
    }
    readOperations.pushBack(heap.allocator(), .{ .buf = data, .tcb = tasks.currentTcb }) catch return error.AllocationError;
}

fn pipeWrite(data: []const u8) tasks.Pipe.Error!void {
    if (writeOperations.len == 0) {
        setOp(data, .write);
    }
    writeOperations.pushBack(heap.allocator(), .{ .buf = data, .tcb = tasks.currentTcb }) catch return error.AllocationError;
}

pub fn init() !void {
    imx.clockControlModule.ccm.serialClockDivider1.uartClockSelector = .pll3Div6;
    imx.clockControlModule.ccm.serialClockDivider1.dividerForUartClockPodfMinusOne = 0;

    try interrupt.registerAndEnableIRQ("DMA0_DMA16", imx.interrupt.makeISR(&irqHandler));

    try tasks.Pipe.createGlobalPipe("LPUART1", &pipeRead, &pipeWrite);

    const uartSrcClock: u32 = if (imx.clockControlModule.ccm.serialClockDivider1.uartClockSelector == .pll3Div6)
        (imx.clockControlModule.ccmAnalog.usb1_480mhzPll.data.get() / 6) / (imx.clockControlModule.ccm.serialClockDivider1.dividerForUartClockPodfMinusOne + 1)
    else
        imx.clockControlModule.xtalOscillator.getClockHz() / (imx.clockControlModule.ccm.serialClockDivider1.dividerForUartClockPodfMinusOne + 1);

    try imx.lpuart.lpuart1.init(.{
        .srcClockHz = uartSrcClock,
        .baudRateBitsPerSecond = 460800,
    });

    imx.clockControlModule.ccm.gating5.dma = .onWhileInRunOrWaitMode;

    imx.dma.edmaControl.enableMinorLoopMapping = false;
    imx.dma.edmaControl.haltOnError = true;

    var tcd = txChannel.edmaTcd.*;
    tcd.sourceAddressOffset = 1;
    tcd.transferAttributes = .{
        .destinationAddressModulo = 0,
        .destinationDataTransferSize = .@"8bit",
        .sourceAddressModulo = 0,
        .sourceDataTransferSize = .@"8bit",
    };
    tcd.minorByteCountOrOffset = .{ .minorByteCount = 1 };
    tcd.destinationAddress = @intFromPtr(imx.lpuart.lpuart1.getDataByteAddress());
    tcd.destinationAddressOffset = 0;
    tcd.lastDestinationAddressAdjustmentScatterGatherAddress = 0;
    tcd.lastSourceAddressAdjustment = 0;
    tcd.controlAndStatus = .{
        .start = false,
        .interruptOnMajorCountComplete = false,
        .interruptOnMajorCountHalfComplete = false,
        .disableRequestOnMajorCountComplete = true,
        .enableChannelLinkOnMajorLoopComplete = false,
        .bandwidthControl = .noStall,
        .channelActive = false,
        .channelDone = false,
        .enableScatterGather = false,
        .majorLoopChannelLinkChannelNumber = 0,
        ._pad0 = 0,
    };
    txChannel.edmaTcd.* = tcd;

    tcd.sourceAddress = @intFromPtr(imx.lpuart.lpuart1.getDataByteAddress());
    tcd.sourceAddressOffset = 0;

    rxChannel.edmaTcd.* = tcd;

    imx.dma.enableRequestRegister.* = 0;
    asm volatile (
        \\DSB
        \\ISB
    );

    txChannel.muxConfiguration.* = .{
        .alwaysOn = false,
        .enable = true,
        .requestSource = .LPUART1_Tx,
        .triggerOn = false,
    };
    rxChannel.muxConfiguration.* = .{
        .alwaysOn = false,
        .enable = true,
        .requestSource = .LPUART1_Rx,
        .triggerOn = false,
    };

    imx.dma.enableErrorInterruptRegister.* |= 1 | (1 << 16);
}
