const imx = @import("libIMXRT1064");

pub fn init() !void {
    imx.clockControlModule.ccm.serialClockDivider1.uartClockSelector = .pll3Div6;
    imx.clockControlModule.ccm.serialClockDivider1.dividerForUartClockPodfMinusOne = 0;

    const uartSrcClock: u32 = if (imx.clockControlModule.ccm.serialClockDivider1.uartClockSelector == .pll3Div6)
        (imx.clockControlModule.ccmAnalog.usb1_480mhzPll.data.get() / 6) / (imx.clockControlModule.ccm.serialClockDivider1.dividerForUartClockPodfMinusOne + 1)
    else
        imx.clockControlModule.xtalOscillator.getClockHz() / (imx.clockControlModule.ccm.serialClockDivider1.dividerForUartClockPodfMinusOne + 1);

    try imx.lpuart.lpuart1.init(.{ .srcClockHz = uartSrcClock, .baudRateBitsPerSecond = 460800 });
}
