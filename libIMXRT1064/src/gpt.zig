const GPT = extern struct {
    control: packed struct(u32) {
        const InputCaptureMode = enum(u2) {
            disabled = 0,
            captureOnRisingEdge = 1,
            captureOnFallingedge = 2,
            captureOnBothEdges = 3,
        };
        const OutputCompareMode = enum(u3) {
            disabled = 0,
            togglePin = 1,
            clearPin = 2,
            setOutputPin = 3,
            clockPulseOnPin = 4,
        };

        enable: bool = false,
        resetCountersOnEnable: bool,
        enableInDebugMode: bool,
        enableInWaitMode: bool,
        enableInDozeMode: bool,
        enableInStopMode: bool,
        clockSource: enum(u3) {
            none = 0,
            peripheralClock = 1,
            highFrequencyReferenceClock = 2,
            externalClock = 3,
            lowFrequencyReferenceClock = 4,
            crystalOscillator24M = 5,
        },
        behaviourOnCompareEvent: enum(u1) {
            restart = 0,
            continueToOverflow = 1,
        },
        enable24MHzInput: bool,
        _pad0: u4 = 0,
        softwareReset: bool = false,
        inputCapture1Mode: InputCaptureMode,
        inputCapture2Mode: InputCaptureMode,
        outputCompare1Mode: OutputCompareMode,
        outputCompare2Mode: OutputCompareMode,
        outputCompare3Mode: OutputCompareMode,
        forceOutputCompare1Now: bool = false,
        forceOutputCompare2Now: bool = false,
        forceOutputCompare3Now: bool = false,
    },
    prescaler: packed struct(u32) {
        denominatorMinusOne: u12,
        denominator24MMinusOne: u4,
        _pad0: u16 = 0,
    },
    status: packed struct(u32) {
        outputCompare1Occurred: bool = true,
        outputCompare2Occurred: bool = true,
        outputCompare3Occurred: bool = true,
        inputCapture1Occurred: bool = true,
        inputCapture2Occurred: bool = true,
        rolledOver: bool = true,
        _pad0: u26 = 0,
    },
    interrupt: packed struct(u32) {
        outputCompare1InterruptEnable: bool = false,
        outputCompare2InterruptEnable: bool = false,
        outputCompare3InterruptEnable: bool = false,
        inputCapture1InterruptEnable: bool = false,
        inputCapture2InterruptEnable: bool = false,
        rolloverInterruptEnable: bool = false,
        _pad0: u26 = 0,
    },
    outputCompare1: u32,
    outputCompare2: u32,
    outputCompare3: u32,
    inputCapture1: u32,
    inputCapture2: u32,
    counter: u32,
};

pub const gpt1: *volatile GPT = @ptrFromInt(0x401EC000);
pub const gpt2: *volatile GPT = @ptrFromInt(0x401F0000);
