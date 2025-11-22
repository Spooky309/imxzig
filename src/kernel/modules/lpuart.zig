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

fn irqHandler() callconv(.c) void {
    if (imx.lpuart.lpuart1.transmitBufferEmpty()) {
        while (writeOperations.len != 0) {
            const writeOp = &writeOperations.buffer[writeOperations.head];
            const bytesWritten = imx.lpuart.lpuart1.writeOut(writeOp.buf);
            if (bytesWritten == writeOp.buf.len) {
                writeOp.tcb.prod();
                _ = writeOperations.popFront();
            } else {
                writeOp.buf = writeOp.buf[bytesWritten..writeOp.buf.len];
                break;
            }
        }
    }

    if (imx.lpuart.lpuart1.receiveBufferFull()) {
        while (readOperations.len != 0) {
            const readOp = &readOperations.buffer[readOperations.head];
            const bytesRead = imx.lpuart.lpuart1.readIn(readOp.buf);
            if (bytesRead == readOp.buf.len) {
                readOp.tcb.prod();
                _ = readOperations.popFront();
            } else {
                readOp.buf = readOp.buf[bytesRead..readOp.buf.len];
                break;
            }
        }
    }

    if (writeOperations.len == 0) {
        imx.lpuart.lpuart1.setTransmitBufferEmptyInterruptEnabled(false);
    }
    if (readOperations.len == 0) {
        imx.lpuart.lpuart1.setReceiveBufferFullInterruptEnable(false);
    }
}

fn pipeRead(data: []u8) tasks.Pipe.Error!void {
    readOperations.pushBack(heap.allocator(), .{ .buf = data, .tcb = tasks.currentTcb }) catch return error.AllocationError;
    imx.lpuart.lpuart1.setReceiveBufferFullInterruptEnable(true);
}

fn pipeWrite(data: []const u8) tasks.Pipe.Error!void {
    writeOperations.pushBack(heap.allocator(), .{ .buf = data, .tcb = tasks.currentTcb }) catch return error.AllocationError;
    imx.lpuart.lpuart1.setTransmitBufferEmptyInterruptEnabled(true);
}

pub fn init() !void {
    imx.clockControlModule.ccm.serialClockDivider1.uartClockSelector = .pll3Div6;
    imx.clockControlModule.ccm.serialClockDivider1.dividerForUartClockPodfMinusOne = 0;

    const uartSrcClock: u32 = if (imx.clockControlModule.ccm.serialClockDivider1.uartClockSelector == .pll3Div6)
        (imx.clockControlModule.ccmAnalog.usb1_480mhzPll.data.get() / 6) / (imx.clockControlModule.ccm.serialClockDivider1.dividerForUartClockPodfMinusOne + 1)
    else
        imx.clockControlModule.xtalOscillator.getClockHz() / (imx.clockControlModule.ccm.serialClockDivider1.dividerForUartClockPodfMinusOne + 1);

    try tasks.Pipe.createGlobalPipe("LPUART1", &pipeRead, &pipeWrite);

    try interrupt.registerAndEnableIRQ("LPUART1", imx.interrupt.makeISR(&irqHandler));

    try imx.lpuart.lpuart1.init(.{
        .srcClockHz = uartSrcClock,
        .baudRateBitsPerSecond = 460800,
    });
}
