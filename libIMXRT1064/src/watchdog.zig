pub const Watchdog = extern struct {
    controlRegister: packed struct(u16) {
        offInLowPowerMode: bool,
        offInDebugMode: bool,
        enable: bool,
        triggerWdogBOnTimeout: bool,
        softwareReset: enum(u1) { reset = 0, dontReset = 1 },
        softwareWdogB: enum(u1) { reset = 0, dontReset = 1 },
        softwareResetType: enum(u1) { old = 0, new = 1 },
        offInWaitMode: bool,
        timeoutInHalfSeconds: u8,
    },
    serviceRegister: enum(u16) {
        serviceSequence0 = 0b0101010101010101,
        serviceSequence1 = 0b1010101010101010,
    },
    resetStatus: packed struct(u16) {
        itWasASoftwareReset: bool,
        itWasATimeoutReset: bool,
        _pad0: u2,
        itWasAPowerOnReset: bool,
        _pad2: u11,
    },
    interruptControl: packed struct(u16) {
        howLongBeforeTimeoutInHalfSeconds: u8,
        _pad0: u6,
        interruptHasOccurred: bool,
        enableInterrupt: bool,
    },
    miscControl: packed struct(u16) {
        powerDownEnable: bool,
        _pad0: u15,
    },

    pub inline fn disable(self: *volatile Watchdog) void {
        self.miscControl.powerDownEnable = false;
        self.controlRegister.enable = false;
    }
};

pub const RTWatchdog = extern struct {
    controlAndStatus: packed struct(u32) {
        enableInStopMode: bool,
        enableInWaitMode: bool,
        enableInDebugMode: bool,
        testMode: enum(u2) {
            disabled = 0,
            userModeEnabled = 1,
            testModeEnabledLowByte = 2,
            testModeEnabledHighByte = 3,
        },
        allowUpdates: bool,
        watchdogInterrupt: bool,
        enable: bool,
        clockSource: enum(u2) {
            busClock = 0,
            lpoClock = 1,
            internalClock = 2,
            externalReferenceClock = 3,
        },
        reconfigSuccessful: bool,
        unlocked: bool,
        clockPrescalerEnabled: bool,
        use32BitRefreshUnlockWriteCommands: bool,
        interruptHasOccurred: bool,
        windowModeEnabled: bool,
        _pad0: u16,
    },
    count: u32,
    timeoutValue: packed struct(u32) {
        val: u16,
        _pad0: u16,
    },
    window: u32, // not implemented

    pub inline fn disable(self: *volatile RTWatchdog) bool {
        if (self.controlAndStatus.use32BitRefreshUnlockWriteCommands) {
            self.count = 0xD928C520;
        } else {
            self.count = 0xC520;
            self.count = 0xD928;
        }
        self.timeoutValue.val = 0xFFFF;
        var w = self.controlAndStatus;
        w.enable = false;
        w.allowUpdates = true;
        self.controlAndStatus = w;
        asm volatile (
            \\ISB
            \\DSB
        );
        return self.controlAndStatus.reconfigSuccessful;
    }
};

pub const WDOG1: *volatile Watchdog = @ptrFromInt(0x400B8000);
pub const WDOG2: *volatile Watchdog = @ptrFromInt(0x400D0000);
pub const RTWDOG: *volatile RTWatchdog = @ptrFromInt(0x400BC000);
