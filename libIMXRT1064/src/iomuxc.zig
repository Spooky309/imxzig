const SampleLvSource = enum(u1) { xbar = 0, synced_sample_lv = 1 };

const SizeNibble = enum(u4) {
    @"0" = 0,
    @"4KiB" = 0b0011,
    @"8KiB" = 0b0100,
    @"16KiB" = 0b0101,
    @"32KiB" = 0b0110,
    @"64KiB" = 0b0111,
    @"128KiB" = 0b1000,
    @"256KiB" = 0b1001,
    @"512KiB" = 0b1010,
};

const GPR14_TYPE = packed struct(u32) {
    acmp1Reduce: bool,
    acmp2Reduce: bool,
    acmp3Reduce: bool,
    acmp4Reduce: bool,
    acmp1Increase: bool,
    acmp2Increase: bool,
    acmp3Increase: bool,
    acmp4Increase: bool,
    acmp1SampleLvSource: SampleLvSource,
    acmp2SampleLvSource: SampleLvSource,
    acmp3SampleLvSource: SampleLvSource,
    acmp4SampleLvSource: SampleLvSource,
    _pad0: u4,
    itcmTotalSize: SizeNibble,
    dtcmTotalSize: SizeNibble,
    _pad1: u8,
};

const GPR16_TYPE = packed struct(u32) {
    itcmEnable: bool,
    dtcmEnable: bool,
    flexramBankConfigSelect: enum(u2) { fuse, flexram_bank_cfg },
    _pad0: u4,
    initialVtorValue: u24,
};

const GPR_TYPE = extern struct {
    GPR0: u32,
    GPR1: u32,
    GPR2: u32,
    GPR3: u32,
    GPR4: u32,
    GPR5: u32,
    GPR6: u32,
    GPR7: u32,
    GPR8: u32,
    GPR9: u32,
    GPR10: u32,
    GPR11: u32,
    GPR12: u32,
    GPR13: u32,
    GPR14: GPR14_TYPE,
    GPR15: u32,
    GPR16: GPR16_TYPE,
    GPR17: u32,
    GPR18: u32,
    GPR19: u32,
    GPR20: u32,
    GPR21: u32,
    GPR22: u32,
    GPR23: u32,
    GPR24: u32,
    GPR25: u32,
    GPR26: u32,
    GPR27: u32,
    GPR28: u32,
    GPR29: u32,
    GPR30: u32,
    GPR31: u32,
    GPR32: u32,
    GPR33: u32,
    GPR34: u32,
};

pub const SW_PAD_CTL_PAD_GPIO_REGISTER = packed struct(u32) {
    useFastSlewRate: bool,
    _pad0: u2 = 0,
    driveStrength: enum(u3) {
        outputDriverDisabled = 0,
        r0_150ohm_at_3_3v_260_ohm_at_1_8v = 1,
        r0_divided_2 = 2,
        r0_divided_3 = 3,
        r0_divided_4 = 4,
        r0_divided_5 = 5,
        r0_divided_6 = 6,
        r0_divided_7 = 7,
    },
    speed: enum(u2) {
        slow_50mhz = 0,
        medium_100mhz = 1,
        fast_150mhz = 2,
        max_200mhz = 3,
    },
    _pad1: u3 = 0,
    openDrainEnabled: bool,
    pullKeeperEnabled: bool,
    pullKeepSelect: enum(u1) { keeper = 0, pull = 1 },
    pullUpDown: enum(u2) {
        pull_down_100k_ohm = 0,
        pull_up_47k_ohm = 1,
        pull_up_100k_ohm = 2,
        pull_up_22k_ohm = 3,
    },
    hysteresisEnabled: bool,
    _pad2: u15 = 0,
};

pub const SW_PAD_CTL_PAD_GPIO = struct {
    AD_B0: [16]SW_PAD_CTL_PAD_GPIO_REGISTER,
    AD_B1: [16]SW_PAD_CTL_PAD_GPIO_REGISTER,
    B0: [16]SW_PAD_CTL_PAD_GPIO_REGISTER,
    B1: [16]SW_PAD_CTL_PAD_GPIO_REGISTER,
};

pub const SW_MUX_CTL_PAD_GPIO_SOFTWARE_INPUT_ON_FIELD = enum(u1) {
    inputPathDeterminedByFunctionality = 0,
    forceInputPath = 1,
};

fn makeSwMuxCtlPadGpioRegisterType(muxModeType: type) type {
    if (@bitSizeOf(muxModeType) != 3) @compileError("swMuxCtlPadGpioRegister muxMode must be 3 bits wide.");
    return packed struct(u32) {
        muxMode: muxModeType,
        softwareInputOn: SW_MUX_CTL_PAD_GPIO_SOFTWARE_INPUT_ON_FIELD,
        _pad0: u28 = 0,
    };
}

pub const UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER = makeSwMuxCtlPadGpioRegisterType(u3);

// There may be a way to auto generate these enums, many of them seem to follow a pattern.
//  Needs to be verified though. For now I'm just going to add them as I go.
// Basically, I think if we make structs to define each of the different things like
//  lcd_data[x], flexio[x]_flexio[y], then as long as they are ordered properly
//  we could generate all of this, I think. They tend to be in order.
pub const SW_MUX_CTL_PAD_GPIO = extern struct {
    AD_B0: extern struct {
        @"00": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"01": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"02": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"03": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"04": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"05": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"06": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"07": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"08": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"09": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"10": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"11": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"12": makeSwMuxCtlPadGpioRegisterType(enum(u3) {
            lpi2c4_scl = 0,
            ccm_pmic_ready = 1,
            lpuart1_tx = 2,
            wdog2_wdog_b = 3,
            flexpwm1_pwmx02 = 4,
            gpio1_io12 = 5,
            enet_1588_event1_out = 6,
            nmi_glue_nmi = 7,
        }),
        @"13": makeSwMuxCtlPadGpioRegisterType(enum(u3) {
            lpi2c4_sda = 0,
            gpt1_clk = 1,
            lpuart1_rx = 2,
            ewm_out_b = 3,
            flexpwm1_pwmx03 = 4,
            gpio1_io13 = 5,
            enet_1588_event1_in = 6,
            ref_clk_24m = 7,
        }),
        @"14": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"15": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
    },
    AD_B1: extern struct {
        @"00": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"01": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"02": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"03": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"04": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"05": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"06": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"07": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"08": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"09": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"10": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"11": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"12": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"13": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"14": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"15": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
    },
    B0: extern struct {
        @"00": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"01": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"02": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"03": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"04": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"05": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"06": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"07": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"08": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"09": makeSwMuxCtlPadGpioRegisterType(enum(u3) {
            lcd_data05 = 0,
            qtimer4_timer0 = 1,
            flexpwm2_pwmb01 = 2,
            lpuart3_rx = 3,
            flexio2_flexio09 = 4,
            gpio2_io09 = 5,
            src_boot_cfg05 = 6,
            enet2_rdata02 = 7,
        }),
        @"10": makeSwMuxCtlPadGpioRegisterType(enum(u3) {
            lcd_data06 = 0,
            qtimer4_timer1 = 1,
            flexpwm2_pwma02 = 2,
            sai1_tx_data03 = 3,
            flexio2_flexio10 = 4,
            gpio2_io10 = 5,
            src_boot_cfg06 = 6,
            enet2_crs = 7,
        }),
        @"11": makeSwMuxCtlPadGpioRegisterType(enum(u3) {
            lcd_data07 = 0,
            qtimer4_timer2 = 1,
            flexpwm2_pwmb02 = 2,
            sai1_tx_data02 = 3,
            flexio2_flexio11 = 4,
            gpio2_io11 = 5,
            src_boot_cfg07 = 6,
            enet2_col = 7,
        }),
        @"12": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"13": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"14": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"15": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
    },
    B1: extern struct {
        @"00": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"01": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"02": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"03": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"04": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"05": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"06": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"07": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"08": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"09": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"10": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"11": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"12": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"13": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"14": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
        @"15": UNKNOWN_SW_MUX_CTL_PAD_GPIO_REGISTER,
    },
};

pub const GPR: *volatile GPR_TYPE = @ptrFromInt(0x400AC000);
pub const swPadCtlPadGpio: *volatile SW_PAD_CTL_PAD_GPIO = @ptrFromInt(0x401F82AC);
pub const swMuxPadGpio: *volatile SW_MUX_CTL_PAD_GPIO = @ptrFromInt(0x401F80BC);
