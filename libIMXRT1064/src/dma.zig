const builtin = @import("std").builtin;

const MuxConfiguration = packed struct(u32) {
    // Add more as you go :)
    requestSource: enum(u7) {
        LPUART1_Tx = 2,
        LPUART1_Rx = 3,
    },
    _pad0: u22 = 0,
    alwaysOn: bool,
    triggerOn: bool,
    enable: bool,
};

const TCD = extern struct {
    const DataTransferSize = enum(u3) {
        @"8bit" = 0,
        @"16bit" = 1,
        @"32bit" = 2,
        @"64bit" = 3,
        @"32ByteBurst" = 5,
    };
    sourceAddress: u32,
    sourceAddressOffset: u16,
    transferAttributes: packed struct(u16) {
        destinationDataTransferSize: DataTransferSize,
        destinationAddressModulo: u5,
        sourceDataTransferSize: DataTransferSize,
        sourceAddressModulo: u5,
    },
    minorByteCountOrOffset: extern union {
        minorByteCount: u32,
        minorLoopOffsetDisabled: packed struct(u32) {
            minorByteTransferCount: u30,
            destinationMinorLoopOffsetEnable: bool,
            sourceMinorLoopOffsetEnable: bool,
        },
        minorLoopOffsetEnabled: packed struct(u32) {
            minorByteTransferCount: u10,
            offset: u20,
            destinationMinorLoopOffsetEnable: bool,
            sourceMinorLoopOffsetEnable: bool,
        },
    },
    lastSourceAddressAdjustment: u32,
    destinationAddress: u32,
    destinationAddressOffset: u16,
    minorLoopLink: extern union {
        disabled: packed struct(u16) {
            currentMajorIterationCount: u15,
            enableChannelLinkOnMinorLoopComplete: bool,
        },
        enabled: packed struct(u16) {
            currentMajorIterationCount: u9,
            minorLoopLinkChannelNumber: u5,
            _pad0: u1,
            enableChannelLinkOnMinorLoopComplete: bool,
        },
    },
    lastDestinationAddressAdjustmentScatterGatherAddress: u32,
    controlAndStatus: packed struct(u16) {
        start: bool,
        interruptOnMajorCountComplete: bool,
        interruptOnMajorCountHalfComplete: bool,
        disableRequestOnMajorCountComplete: bool,
        enableScatterGather: bool,
        enableChannelLinkOnMajorLoopComplete: bool,
        channelActive: bool,
        channelDone: bool,
        majorLoopChannelLinkChannelNumber: u5,
        _pad0: u1,
        bandwidthControl: enum(u2) {
            noStall = 0,
            stall4Cycles = 1,
            stall8Cycles = 2,
        },
    },
    beginningMinorLoopLink: extern union {
        disabled: packed struct(u16) {
            startingMajorIterationCount: u15,
            enableMinorLoopLink: bool,
        },
        enabled: packed struct(u16) {
            startingMajorIterationCount: u9,
            linkChannelNumber: u5,
            _pad0: u1,
            enableMinorLoopLink: bool,
        },
    },
};

const EDMAControl = packed struct(u32) {
    _pad0: u1,
    stopInDebug: bool,
    enableRoundRobinChannelArbitration: bool,
    enableRoundRobinGroupArbitration: bool,
    haltOnError: bool,
    halt: bool,
    continuousLinkMode: bool,
    enableMinorLoopMapping: bool,
    channelGroup0Priority: u1,
    _pad1: u1,
    channelGroup1Priority: u1,
    _pad2: u5,
    errorCancelTransfer: bool,
    cancelTransfer: bool,
    _pad3: u6,
    versionNumber: u7,
    active: bool,
};

const EDMAErrorStatus = packed struct(u32) {
    destinationBusError: bool,
    sourceBusError: bool,
    scatterGatherConfigError: bool,
    nbytesOrCiterConfigError: bool,
    destinationOffsetError: bool,
    destinationAddressError: bool,
    sourceOffsetError: bool,
    sourceAddressError: bool,
    errorChannelNumber: u5,
    _pad0: u1,
    channelPriorityError: bool,
    groupPriorityError: bool,
    transferCancelled: bool,
    _pad2: u14,
    anyError: bool,
};

const EnableRequestRegister = u32;

pub const Channel = struct {
    muxConfiguration: *volatile MuxConfiguration,
    edmaTcd: *volatile TCD,
};

fn makeChannels() [32]Channel {
    var c: [32]Channel = undefined;
    inline for (0..32) |i| {
        c[i] = .{
            .muxConfiguration = @ptrFromInt(0x400EC000 + (i * @sizeOf(MuxConfiguration))),
            .edmaTcd = @ptrFromInt(0x400E9000 + (i * @sizeOf(TCD))),
        };
    }
    return c;
}

pub const channels = makeChannels();
pub const edmaControl: *volatile EDMAControl = @ptrFromInt(0x400E8000);
pub const edmaErrorStatus: *volatile EDMAErrorStatus = @ptrFromInt(0x400E8004);
pub const enableErrorInterruptRegister: *volatile u32 = @ptrFromInt(0x400E8014);
pub const interruptRequests: *volatile u32 = @ptrFromInt(0x400E8024);
pub const clearInterruptRequests: *volatile u8 = @ptrFromInt(0x400E801F);
pub const errors: *volatile u32 = @ptrFromInt(0x400E802C);
pub const enableRequestRegister: *volatile EnableRequestRegister = @ptrFromInt(0x400E800C);
