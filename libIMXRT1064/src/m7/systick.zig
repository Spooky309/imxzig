const SysTickControlAndStatusRegister = packed struct(u32) {
    enabled: bool,
    triggerExceptionOnCountToZero: bool,
    clockSource: enum(u1) {
        externalClock = 0,
        processorClock = 1,
    },
    _pad0: u13 = 0,
    hasCountedToZeroSinceLastRead: bool,
    _pad2: u15 = 0,
};

const SysTickReloadValueRegister = packed struct(u32) {
    valueToLoadWhenZeroReached: u24,
    _pad0: u8,
};

const SysTickCurrentValueRegister = u32;

const SysTickCalibrationValueRegister = packed struct(u32) {
    reloadValueFor10msTiming: u24,
    _pad0: u6,
    valueIsSkewedByClockFrequency: bool,
    noReferenceClock: bool,
};

pub const controlAndStatus: *volatile SysTickControlAndStatusRegister = @ptrFromInt(0xE000E010);
pub const reloadValue: *volatile SysTickReloadValueRegister = @ptrFromInt(0xE000E014);
pub const currentValue: *volatile SysTickCurrentValueRegister = @ptrFromInt(0xE000E018);
pub const calibrationValue: *volatile SysTickCalibrationValueRegister = @ptrFromInt(0xE000E01C);
