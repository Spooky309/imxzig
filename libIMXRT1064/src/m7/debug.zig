const CoreDebug = extern struct {
    haltingControlAndStatusRegister: packed struct(u32) {
        haltingDebugEnable: bool,
        processorHalted: bool,
        processorSingleStepEnabled: bool,
        maskInterrupts: bool,
        _pad0: u1,
        allowImpreciseEntry: bool,
        _pad1: u10,
        dcrdrHandshakeFlag: bool,
        processorIsInDebugState: bool,
        processorIsSleeping: bool,
        processorIsLockedUp: bool,
        _pad2: u4,
        processorHasRetiredInstructions: bool,
        processorWasReset: bool,
        _pad3: u6,
    },
    DCRSR: u32,
    DCRDR: u32,
    DEMCR: u32,
};

pub const coreDebug: *volatile CoreDebug = @ptrFromInt(0xE000EDF0);
