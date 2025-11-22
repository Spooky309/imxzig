const std = @import("std");
const iomuxc = @import("iomuxc.zig");
const clockControlModule = @import("clockControlModule.zig");

fn getFIFOSizeFromRegisterValue(val: u5) usize {
    if (val == 0) return 1;
    return (@as(usize, 1) << (val + 1));
}

const LPUARTRegister = extern struct {
    versionID: packed struct(u32) {
        feature: u16,
        minor: u8,
        major: u8,
    },
    parameters: packed struct(u32) {
        txFifoSizeInWordsLog2: u8,
        rxFifoSizeInWordsLog2: u8,
        _pad0: u16,
    },
    global: packed struct(u32) {
        _pad0: u1,
        resetRequest: bool,
        _pad1: u30,
    },
    pinConfig: packed struct(u32) {
        inputTriggerSelect: enum(u2) {
            disabled = 0,
            usedInsteadOfRXDPinInput = 1,
            usedInsteadOfCTS_BPinInput = 2,
            ANDedWithTXDPinOutput = 3,
        },
        _pad0: u30,
    },
    baudRate: packed struct(u32) {
        moduloDivisor: u13,
        numStopBits: enum(u1) { one = 0, two = 1 },
        rxInputActiveEdgeInterruptEnable: bool,
        linBreakDetectInterruptEnable: bool,
        resynchronizationDisable: bool,
        bothEdgeSampling: enum(u1) { risingEdgeOnly = 0, risingAndFallingEdge = 1 },
        matchConfiguration: enum(u2) {
            addressMatchWakeup = 0,
            idleMatchWakeup = 1,
            matchOnAndMatchOff = 2,
            enableRWUOnDataMatchAndMatchOnOffForTransmitterCTSInput = 3,
        },
        receiverIdleDMAEnable: bool,
        receiverFullDMAEnable: bool,
        _pad0: u1,
        transmitterDMAEnable: bool,
        oversamplingRatio: enum(u5) {
            @"4RequiresBothEdgeSet" = 3,
            @"5RequiresBothEdgeSet" = 4,
            @"6RequiresBothEdgeSet" = 5,
            @"7RequiresBothEdgeSet" = 6,
            @"8" = 7,
            @"9" = 8,
            @"10" = 9,
            @"11" = 10,
            @"12" = 11,
            @"13" = 12,
            @"14" = 13,
            @"15" = 14,
            @"16" = 15,
            @"17" = 16,
            @"18" = 17,
            @"19" = 18,
            @"20" = 19,
            @"21" = 20,
            @"22" = 21,
            @"23" = 22,
            @"24" = 23,
            @"25" = 24,
            @"26" = 25,
            @"27" = 26,
            @"28" = 27,
            @"29" = 28,
            @"30" = 29,
            @"31" = 30,
            @"32" = 31,
        },
        useTenBitMode: bool,
        matchAddressModeEnable2: bool,
        matchAddressModeEnable1: bool,
    },
    status: packed struct(u32) {
        _pad0: u14,
        match2Flag: bool,
        match1Flag: bool,
        parityErrorFlag: bool,
        framingErrorFlag: bool,
        noiseFlag: bool,
        receiverOverrunFlag: bool,
        idleLineFlag: bool,
        receiveDataRegisterFullFlag: bool,
        transmissionCompleteFlag: bool,
        transmitDataRegisterEmptyFlag: bool,
        receiverActiveFlag: bool,
        LINBreakDetectionEnable: bool,
        breakCharacterGenerationLength: enum(u1) { @"9to13BitTimes" = 0, @"12to15BitTimes" = 1 },
        setIdleBitDuringReceiveStandbyState: bool,
        receiveDataInversion: bool,
        endianness: enum(u1) { big = 0, small = 1 },
        RXDPinActiveEdgeInterruptFlag: bool,
        LINBreakDetectInterruptFlag: bool,
    },
    control: packed struct(u32) {
        useOddParity: bool,
        parityEnabled: bool,
        idleLineType: enum(u1) { afterStartBit = 0, afterStopBit = 1 },
        receiverWakeupMethod: enum(u1) { idleLineWakeup = 0, addressMarkWakeup = 1 },
        use9BitCharacters: bool,
        receiverSourceWhenLoopModeEnabled: enum(u1) { loopback = 0, txdPin },
        disableInDozeMode: bool,
        enableLoopMode: bool,
        numIdleCharactersLog2: u3,
        use7BitCharacters: bool,
        _pad0: u2,
        match2InterruptEnable: bool,
        match1InterruptEnable: bool,
        sendBreak: bool,
        receiverInStandbyWaitingForWakeupCondition: bool,
        receiverEnable: bool,
        transmitterEnable: bool,
        idleLineInterruptEnable: bool,
        receiverBufferFullInterruptEnable: bool,
        transmissionCompleteInterruptEnable: bool,
        transmissionBufferEmptyInterruptEnable: bool,
        parityErrorInterruptEnable: bool,
        framingErrorInterruptEnable: bool,
        noiseErrorInterruptEnable: bool,
        overrunInterruptEnable: bool,
        transmitDataInversion: bool,
        txdPinDirectionInSingleWireMode: enum(u1) { input = 0, output = 1 },
        receiveBit9TransmitBit8: bool,
        receiveBit8TransmitBit9: bool,
    },
    data: packed struct(u32) {
        readOrWriteBuffer: u10,
        _pad0: u1,
        receiverWasIdleBeforeReceivingThisCharacter: bool,
        receiveBufferEmpty: bool,
        frameError: bool,
        parityError: bool,
        noisy: bool,
        _pad1: u16,
    },
    matchAddress: packed struct(u32) {
        matchAddress1: u9,
        _pad0: u7,
        matchAddress2: u9,
        _pad1: u7,
    },
    modemIrda: packed struct(u32) {
        transmitterClearToSendEnable: bool = false,
        transmitterRequestToSendEnable: bool = false,
        transmitterRequestToSendPoalrity: bool = false,
        receiverRequestToSendEnable: bool = false,
        transmitCTSConfiguration: bool = false,
        transmitCTSSource: bool = false,
        _pad0: u2 = 0,
        receiveRTSConfiguration: u2 = 0,
        _pad1: u6 = 0,
        transmitterNarrowPulse: u2 = 0,
        infraredEnable: bool = false,
        _pad2: u13 = 0,
    },
    fifo: packed struct(u32) {
        rxFifoSizeInWordsLog2: u3,
        rxFifoEnable: bool,
        txFifoSizeInWordsLog2: u3,
        txFifoEnable: bool,
        rxFifoUnderflowInterruptEnable: bool,
        txFifoOverflowInterruptEnable: bool,
        receiverIdleEmptyEnableAndIfSoHowManyCharactersToWaitForLog2PlusOne: u3,
        _pad0: u1,
        rxFifoFlush: bool,
        txFifoFlush: bool,
        rxFifoUnderflow: bool,
        txFifoOverflow: bool,
        _pad1: u4,
        rxFifoEmpty: bool,
        txFifoEmpty: bool,
        _pad2: u8,
    },
    watermark: packed struct(u32) {
        transmitWatermarkInWords: u2,
        _pad0: u6 = 0,
        wordsInTransmitBuffer: u3 = 0, // Read
        _pad1: u5 = 0,
        receiveWatermarkInWords: u2,
        _pad2: u6 = 0,
        wordsInReceiveBuffer: u3 = 0, // Read
        _pad3: u5 = 0,
    },
};

const Config = struct {
    baudRateBitsPerSecond: u32 = 115200,
    parityMode: enum { disabled, even, odd } = .disabled,
    dataBitsCount: enum { @"8", @"7" } = .@"8",
    msbFirst: bool = false,
    stopBitCount: enum { @"1", @"2" } = .@"1",
    txFifoWatermarkInWords: u2 = 0,
    rxFifoWatermarkInWords: u2 = 1,
    rxIdleType: enum { onStartBit, onStopBit } = .onStartBit,
    rxNumIdleCharactersLog2: u3 = 0,
    enableTx: bool = true,
    enableRx: bool = true,
    srcClockHz: u32,
};

// Right now this is only LPUART1
fn LPUART(
    register: *volatile LPUARTRegister,
    muxPadGpioForTx: anytype,
    muxPadGpioValueForTx: anytype,
    muxPadGpioForRx: anytype,
    muxPadGpioValueForRx: anytype,
    padCtrlTx: anytype,
    padCtrlRx: anytype,
    ccmGateRegister: anytype,
) type {
    return struct {
        var currentConfig: Config = undefined;

        const Error = error{
            BaudRateNotSupported,
        };

        pub fn setTxDMA(val: bool) void {
            register.baudRate.transmitterDMAEnable = val;
        }

        pub fn setRxDMA(val: bool) void {
            register.baudRate.receiverFullDMAEnable = val;
        }

        pub fn getDataByteAddress() *volatile u8 {
            return @as(*volatile u8, @ptrCast(&register.data));
        }

        pub fn init(config: Config) Error!void {
            var baudDiff: u32 = config.baudRateBitsPerSecond;
            var oversamplingRate: u32 = 0;
            var moduloDivisor: u32 = 0;

            // Find an oversampling rate/stop bits that most closely gets the requested baudrate
            for (4..33) |oversamplingRateTry| {
                const computedModuloDivisor = @max(((config.srcClockHz * 10 / (config.baudRateBitsPerSecond * oversamplingRateTry) + 5) / 10), 1);

                const computedBaudRate = (config.srcClockHz / (oversamplingRateTry * computedModuloDivisor));
                const diff = @max(computedBaudRate, config.baudRateBitsPerSecond) - @min(computedBaudRate, config.baudRateBitsPerSecond);
                if (diff <= baudDiff) {
                    baudDiff = diff;
                    oversamplingRate = oversamplingRateTry;
                    moduloDivisor = computedModuloDivisor;
                }
            }

            if (baudDiff > ((config.baudRateBitsPerSecond / 100) * 3)) {
                return error.BaudRateNotSupported;
            }

            currentConfig = config;

            // Tell IOMUXC to hook us up to our pin
            const padConfig = iomuxc.SW_PAD_CTL_PAD_GPIO_REGISTER{
                .useFastSlewRate = false,
                .driveStrength = .r0_divided_6,
                .speed = .fast_150mhz,
                .openDrainEnabled = false,
                .pullKeeperEnabled = true,
                .pullKeepSelect = .keeper,
                .pullUpDown = .pull_down_100k_ohm,
                .hysteresisEnabled = false,
            };
            muxPadGpioForTx.* = .{ .muxMode = muxPadGpioValueForTx, .softwareInputOn = .inputPathDeterminedByFunctionality };
            muxPadGpioForRx.* = .{ .muxMode = muxPadGpioValueForRx, .softwareInputOn = .inputPathDeterminedByFunctionality };
            padCtrlRx.* = padConfig;
            padCtrlTx.* = padConfig;

            var ccmGateState = ccmGateRegister.*;
            ccmGateState = .onWhileInRunOrWaitMode;
            ccmGateRegister.* = ccmGateState;

            var ctrl = register.control;
            ctrl.receiverEnable = false;
            ctrl.transmitterEnable = false;
            register.control = ctrl;

            var baud = register.baudRate;
            baud.bothEdgeSampling = if ((oversamplingRate > 3) and (oversamplingRate < 8)) .risingAndFallingEdge else .risingEdgeOnly;
            baud.oversamplingRatio = @enumFromInt(oversamplingRate - 1);
            baud.moduloDivisor = @truncate(moduloDivisor);
            baud.useTenBitMode = false;
            baud.numStopBits = if (config.stopBitCount == .@"1") .one else .two;
            baud.transmitterDMAEnable = false;
            baud.receiverFullDMAEnable = false;
            baud.receiverIdleDMAEnable = false;
            register.baudRate = baud;

            ctrl = register.control;
            ctrl.parityEnabled = (config.parityMode != .disabled);
            ctrl.useOddParity = config.parityMode == .odd;
            ctrl.use7BitCharacters = (config.dataBitsCount == .@"7" and config.parityMode == .disabled);
            ctrl.use9BitCharacters = (config.dataBitsCount == .@"8" and config.parityMode != .disabled);
            ctrl.idleLineType = if (config.rxIdleType == .onStartBit) .afterStartBit else .afterStopBit;
            ctrl.numIdleCharactersLog2 = config.rxNumIdleCharactersLog2;
            register.control = ctrl;

            const maxRxWatermark = getFIFOSizeFromRegisterValue(register.fifo.rxFifoSizeInWordsLog2) - 1;
            const maxTxWatermark = getFIFOSizeFromRegisterValue(register.fifo.txFifoSizeInWordsLog2) - 1;
            register.watermark = .{
                .receiveWatermarkInWords = @max(1, @min(config.rxFifoWatermarkInWords, maxRxWatermark)),
                .transmitWatermarkInWords = @min(config.txFifoWatermarkInWords, maxTxWatermark),
            };

            var fifo = register.fifo;
            fifo.rxFifoEnable = true;
            fifo.txFifoEnable = true;
            fifo.rxFifoFlush = true;
            fifo.txFifoFlush = true;
            fifo.receiverIdleEmptyEnableAndIfSoHowManyCharactersToWaitForLog2PlusOne = 1;
            register.fifo = fifo;

            // We aren't doing this yet.
            register.modemIrda = .{};

            var status = register.status;
            status.RXDPinActiveEdgeInterruptFlag = true;
            status.idleLineFlag = true;
            status.receiverOverrunFlag = true;
            status.noiseFlag = true;
            status.framingErrorFlag = true;
            status.parityErrorFlag = true;
            status.LINBreakDetectInterruptFlag = true;
            status.match1Flag = true;
            status.match2Flag = true;
            status.endianness = if (config.msbFirst) .small else .big;
            register.status = status;

            ctrl = register.control;
            ctrl.transmitterEnable = true;
            ctrl.receiverEnable = true;
            register.control = ctrl;
        }
        pub fn reader() std.Io.Reader {
            return std.Io.Reader{
                .buffer = &.{},
                .vtable = &readerVtable,
                .seek = 0,
                .end = 0,
            };
        }
        pub fn writer() std.Io.Writer {
            return std.Io.Writer{
                .buffer = &.{},
                .vtable = &writerVtable,
            };
        }
        pub fn writeOutBlocking(data: []const u8) void {
            for (data) |c| {
                while (!register.status.transmitDataRegisterEmptyFlag) {}
                register.data.readOrWriteBuffer = @as(u10, @intCast(c));
            }
            while (!register.status.transmissionCompleteFlag) {}
        }
        pub fn writeChar(wait: bool, c: u8) bool {
            if (wait) {
                while (!register.status.transmitDataRegisterEmptyFlag) {}
            } else if (!register.status.transmitDataRegisterEmptyFlag) {
                return false;
            }
            register.data.readOrWriteBuffer = @intCast(c);
            while (!register.status.transmissionCompleteFlag) {}
            return true;
        }
        pub fn readChar(wait: bool) ?u8 {
            if (wait) {
                while (register.watermark.wordsInReceiveBuffer == 0) {}
            } else if (register.watermark.wordsInReceiveBuffer == 0) {
                return null;
            }
            return @truncate(register.data.readOrWriteBuffer);
        }

        const readerVtable: std.Io.Reader.VTable = .{
            .stream = readerStream,
        };
        fn readerStream(_: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
            var l: ?std.Io.Limit = limit;
            while (l) |lim| {
                if (readChar(false)) |c| {
                    _ = w.write(&.{c}) catch {
                        return std.Io.Reader.StreamError.WriteFailed;
                    };
                } else {
                    return limit.subtract(lim.toInt().?).?.toInt().?;
                }
                l = lim.subtract(1);
            }
            return limit.toInt().?;
        }

        const writerVtable: std.Io.Writer.VTable = .{
            .drain = writerDrain,
        };
        fn writerDrain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
            var numBytesWritten: usize = 0;
            writeOutBlocking(w.buffer[0..w.end]);
            w.end = 0;
            for (0..data.len - 1) |i| {
                writeOutBlocking(data[i]);
                numBytesWritten += data[i].len;
            }
            for (0..splat) |_| {
                writeOutBlocking(data[data.len - 1]);
                numBytesWritten += data[data.len - 1].len;
            }
            return numBytesWritten;
        }
    };
}

pub const lpuart1 = LPUART(
    @ptrFromInt(0x40184000),
    &iomuxc.swMuxPadGpio.AD_B0.@"12",
    @TypeOf(iomuxc.swMuxPadGpio.AD_B0.@"12".muxMode).lpuart1_tx,
    &iomuxc.swMuxPadGpio.AD_B0.@"13",
    @TypeOf(iomuxc.swMuxPadGpio.AD_B0.@"13".muxMode).lpuart1_rx,
    &iomuxc.swPadCtlPadGpio.AD_B0[12],
    &iomuxc.swPadCtlPadGpio.AD_B0[13],
    &clockControlModule.ccm.gating5.lpuart1,
);
