const compconfig = @import("compconfig");
const std = @import("std");

pub const ReturnState = extern struct {
    SP: usize = 0,
    excReturn: usize = 0,
    R4: usize = 0,
    R5: usize = 0,
    R6: usize = 0,
    R7: usize = 0,
    R8: usize = 0,
    R9: usize = 0,
    R10: usize = 0,
    R11: usize = 0,
};

// with no FPU!
pub const StandardStackFrame = extern struct {
    R0: usize = 0,
    R1: usize = 0,
    R2: usize = 0,
    R3: usize = 0,
    R12: usize = 0,
    LR: usize = 0xDEADBEEF,
    PC: usize = 0,
    XPSR: usize = 0x01000000,
};

pub const InterruptHandler = ?*const fn () callconv(.naked) void;

pub fn makeISR(comptime func: anytype) *const fn () callconv(.naked) void {
    const ft = @typeInfo(@typeInfo(@TypeOf(func)).pointer.child);

    if (ft.@"fn".calling_convention != .arm_aapcs_vfp and ft.@"fn".calling_convention != .arm_aapcs) {
        @compileError("makeISR: Function must be C calling convention.");
    }
    if (ft.@"fn".params.len > 1) {
        @compileError("makeISR: Function must have 0-1 parameters.");
    }
    if (ft.@"fn".params.len == 1 and ft.@"fn".params[0].type.? != ReturnState) {
        @compileError("makeISR: Function parameter must be a ReturnState type");
    }

    if (ft.@"fn".params.len == 1) {
        return struct {
            pub fn isr() callconv(.naked) void {
                asm volatile (
                    \\PUSH {LR}
                    \\
                    \\MRS R0, PSP
                    \\MOV R1, LR
                    \\MOV R2, R4
                    \\MOV R3, R5
                    \\PUSH {R6-R11}
                    \\
                    \\BL %[theHandler]
                    \\
                    \\ADD SP, #24
                    \\POP {PC}
                    :
                    : [theHandler] "X" (func),
                );
            }
        }.isr;
    } else {
        return struct {
            pub fn isr() callconv(.naked) void {
                asm volatile (
                    \\B %[theHandler]
                    :
                    : [theHandler] "X" (func),
                );
            }
        }.isr;
    }
}

// Longest interrupt name is GPIO5_Combined_16_31, which is 20 characters.
// So, the message "Unhandled interrupt: GPIO5_Combined_16_31\n" is 42 characters.
// I give a little extra space just in case something bigger is here in the future.
var panickingISRBuffer: [64]u8 = undefined;
fn makePanickingISR(comptime name: []const u8) *const fn () callconv(.c) void {
    return struct {
        pub fn interruptHandler() callconv(.c) void {
            const msg = std.fmt.comptimePrint("Unhandled interrupt: {s}\n", .{name});
            @panic(msg);
        }
    }.interruptHandler;
}

pub fn makeIVT(comptime overrides: VectorTable) VectorTable {
    var ret: VectorTable = overrides;

    const typeInfo = @typeInfo(VectorTable).@"struct";
    inline for (typeInfo.fields) |field| {
        // Don't generate default ISR handler for resetISR, because it's the first thing we run when we start up!
        //  If not set, it will be filled in by boot.zig later.
        if (field.type == InterruptHandler and !std.mem.eql(u8, field.name, "reset") and @field(ret, field.name) == null) {
            const isr = makeISR(makePanickingISR(field.name));
            @field(ret, field.name) = isr;
        }
    }

    return ret;
}

// This can be split up, the first part of the VectorTable should be in M7.
pub const VectorTable = extern struct {
    pub const alignment = std.math.ceilPowerOfTwoAssert(u32, @sizeOf(VectorTable));

    // CM7 defined
    initialStackTop: u32 = compconfig.ocmBase + compconfig.ocmSize, // Put stack at top of OCM, we will move it after we configure DTCM
    reset: InterruptHandler = null,
    nmi: InterruptHandler = null,
    hardFault: InterruptHandler = null,
    mmanFault: InterruptHandler = null,
    busFault: InterruptHandler = null,
    usageFault: InterruptHandler = null,
    _pad0: u32 = 0,
    _pad1: u32 = 0,
    _pad2: u32 = 0,
    _pad3: u32 = 0,
    svc: InterruptHandler = null,
    _pad7: u32 = 0,
    _pad8: u32 = 0,
    pendSV: InterruptHandler = null,
    sysTick: InterruptHandler = null,

    // iMXRT1064 Defined
    DMA0_DMA16: InterruptHandler = null,
    DMA1_DMA17: InterruptHandler = null,
    DMA2_DMA18: InterruptHandler = null,
    DMA3_DMA19: InterruptHandler = null,
    DMA4_DMA20: InterruptHandler = null,
    DMA5_DMA21: InterruptHandler = null,
    DMA6_DMA22: InterruptHandler = null,
    DMA7_DMA23: InterruptHandler = null,
    DMA8_DMA24: InterruptHandler = null,
    DMA9_DMA25: InterruptHandler = null,
    DMA10_DMA26: InterruptHandler = null,
    DMA11_DMA27: InterruptHandler = null,
    DMA12_DMA28: InterruptHandler = null,
    DMA13_DMA29: InterruptHandler = null,
    DMA14_DMA30: InterruptHandler = null,
    DMA15_DMA31: InterruptHandler = null,
    DMA_ERROR: InterruptHandler = null,
    CTI0_ERROR: InterruptHandler = null,
    CTI1_ERROR: InterruptHandler = null,
    CORE: InterruptHandler = null,
    LPUART1: InterruptHandler = null,
    LPUART2: InterruptHandler = null,
    LPUART3: InterruptHandler = null,
    LPUART4: InterruptHandler = null,
    LPUART5: InterruptHandler = null,
    LPUART6: InterruptHandler = null,
    LPUART7: InterruptHandler = null,
    LPUART8: InterruptHandler = null,
    LPI2C1: InterruptHandler = null,
    LPI2C2: InterruptHandler = null,
    LPI2C3: InterruptHandler = null,
    LPI2C4: InterruptHandler = null,
    LPSPI1: InterruptHandler = null,
    LPSPI2: InterruptHandler = null,
    LPSPI3: InterruptHandler = null,
    LPSPI4: InterruptHandler = null,
    CAN1: InterruptHandler = null,
    CAN2: InterruptHandler = null,
    FLEXRAM: InterruptHandler = null,
    KPP: InterruptHandler = null,
    TSC_DIG: InterruptHandler = null,
    GPR_IRQ: InterruptHandler = null,
    LCDIF: InterruptHandler = null,
    CSI: InterruptHandler = null,
    PXP: InterruptHandler = null,
    WDOG2: InterruptHandler = null,
    SNVS_HP_WRAPPER: InterruptHandler = null,
    SNVS_HP_WRAPPER_TZ: InterruptHandler = null,
    SNVS_LP_WRAPPER: InterruptHandler = null,
    CSU: InterruptHandler = null,
    DCP: InterruptHandler = null,
    DCP_VMI: InterruptHandler = null,
    Reserved68: InterruptHandler = null,
    TRNG: InterruptHandler = null,
    SJC: InterruptHandler = null,
    BEE: InterruptHandler = null,
    SAI1: InterruptHandler = null,
    SAI2: InterruptHandler = null,
    SAI3_RX: InterruptHandler = null,
    SAI3_TX: InterruptHandler = null,
    SPDIF: InterruptHandler = null,
    PMU_EVENT: InterruptHandler = null,
    Reserved78: InterruptHandler = null,
    TEMP_LOW_HIGH: InterruptHandler = null,
    TEMP_PANIC: InterruptHandler = null,
    USB_PHY1: InterruptHandler = null,
    USB_PHY2: InterruptHandler = null,
    ADC1: InterruptHandler = null,
    ADC2: InterruptHandler = null,
    DCDC: InterruptHandler = null,
    Reserved86: InterruptHandler = null,
    Reserved87: InterruptHandler = null,
    GPIO1_INT0: InterruptHandler = null,
    GPIO1_INT1: InterruptHandler = null,
    GPIO1_INT2: InterruptHandler = null,
    GPIO1_INT3: InterruptHandler = null,
    GPIO1_INT4: InterruptHandler = null,
    GPIO1_INT5: InterruptHandler = null,
    GPIO1_INT6: InterruptHandler = null,
    GPIO1_INT7: InterruptHandler = null,
    GPIO1_Combined_0_15: InterruptHandler = null,
    GPIO1_Combined_16_31: InterruptHandler = null,
    GPIO2_Combined_0_15: InterruptHandler = null,
    GPIO2_Combined_16_31: InterruptHandler = null,
    GPIO3_Combined_0_15: InterruptHandler = null,
    GPIO3_Combined_16_31: InterruptHandler = null,
    GPIO4_Combined_0_15: InterruptHandler = null,
    GPIO4_Combined_16_31: InterruptHandler = null,
    GPIO5_Combined_0_15: InterruptHandler = null,
    GPIO5_Combined_16_31: InterruptHandler = null,
    FLEXIO1: InterruptHandler = null,
    FLEXIO2: InterruptHandler = null,
    WDOG1: InterruptHandler = null,
    RTWDOG: InterruptHandler = null,
    EWM: InterruptHandler = null,
    CCM_1: InterruptHandler = null,
    CCM_2: InterruptHandler = null,
    GPC: InterruptHandler = null,
    SRC: InterruptHandler = null,
    Reserved115: InterruptHandler = null,
    GPT1: InterruptHandler = null,
    GPT2: InterruptHandler = null,
    PWM1_0: InterruptHandler = null,
    PWM1_1: InterruptHandler = null,
    PWM1_2: InterruptHandler = null,
    PWM1_3: InterruptHandler = null,
    PWM1_FAULT: InterruptHandler = null,
    FLEXSPI2: InterruptHandler = null,
    FLEXSPI: InterruptHandler = null,
    SEMC: InterruptHandler = null,
    USDHC1: InterruptHandler = null,
    USDHC2: InterruptHandler = null,
    USB_OTG2: InterruptHandler = null,
    USB_OTG1: InterruptHandler = null,
    ENET: InterruptHandler = null,
    ENET_1588_Timer: InterruptHandler = null,
    XBAR1_IRQ_0_1: InterruptHandler = null,
    XBAR1_IRQ_2_3: InterruptHandler = null,
    ADC_ETC_IRQ0: InterruptHandler = null,
    ADC_ETC_IRQ1: InterruptHandler = null,
    ADC_ETC_IRQ2: InterruptHandler = null,
    ADC_ETC_ERROR_IRQ: InterruptHandler = null,
    PIT: InterruptHandler = null,
    ACMP1: InterruptHandler = null,
    ACMP2: InterruptHandler = null,
    ACMP3: InterruptHandler = null,
    ACMP4: InterruptHandler = null,
    Reserved143: InterruptHandler = null,
    Reserved144: InterruptHandler = null,
    ENC1: InterruptHandler = null,
    ENC2: InterruptHandler = null,
    ENC3: InterruptHandler = null,
    ENC4: InterruptHandler = null,
    TMR1: InterruptHandler = null,
    TMR2: InterruptHandler = null,
    TMR3: InterruptHandler = null,
    TMR4: InterruptHandler = null,
    PWM2_0: InterruptHandler = null,
    PWM2_1: InterruptHandler = null,
    PWM2_2: InterruptHandler = null,
    PWM2_3: InterruptHandler = null,
    PWM2_FAULT: InterruptHandler = null,
    PWM3_0: InterruptHandler = null,
    PWM3_1: InterruptHandler = null,
    PWM3_2: InterruptHandler = null,
    PWM3_3: InterruptHandler = null,
    PWM3_FAULT: InterruptHandler = null,
    PWM4_0: InterruptHandler = null,
    PWM4_1: InterruptHandler = null,
    PWM4_2: InterruptHandler = null,
    PWM4_3: InterruptHandler = null,
    PWM4_FAULT: InterruptHandler = null,
    ENET2: InterruptHandler = null,
    ENET2_1588_Timer: InterruptHandler = null,
    CAN3: InterruptHandler = null,
    Reserved171: InterruptHandler = null,
    FLEXIO3: InterruptHandler = null,
    GPIO6_7_8_9: InterruptHandler = null,
};

pub const VTOR: **align(VectorTable.alignment) const VectorTable = @ptrFromInt(0xE000ED08);
