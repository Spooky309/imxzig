const imx = @import("libIMXRT1064");
const std = @import("std");

const Error = error{
    CommandNameAlreadyUsed,
};

const CommandFunc = fn (args: []const []const u8) void;

// 128b buffer for registering commands. You can just make this bigger if needed.
//  Maybe if we have a real allocator later on, we can
var registeredCommandsBuffer: [128]u8 = undefined;
var registeredCommandsAllocator = std.heap.FixedBufferAllocator.init(&registeredCommandsBuffer);
var registeredCommands = std.StringHashMap(*const CommandFunc).init(registeredCommandsAllocator.allocator());

var terminalBuffer: [256]u8 = undefined;
var terminalBufferTop: u32 = 0;
var lastCharReceived: u8 = 0;

fn putCommandPrompt() void {
    _ = imx.lpuart.lpuart1.writeChar(true, '>');
    _ = imx.lpuart.lpuart1.writeChar(true, ' ');
}

fn doCommand() !void {
    const cmd = terminalBuffer[0..terminalBufferTop];
    var writer = imx.lpuart.lpuart1.writer();
    _ = imx.lpuart.lpuart1.writeChar(true, '\n');
    _ = try writer.write(cmd);
    _ = imx.lpuart.lpuart1.writeChar(true, '\n');
    if (registeredCommands.get(cmd)) |c| {
        c(&.{});
    } else {
        _ = try writer.write("Unrecognized command\n");
    }
    putCommandPrompt();
    terminalBufferTop = 0;
}

fn receiveChars() !void {
    while (imx.lpuart.lpuart1.readChar(false)) |c| {
        if (c == '\r' or (c == '\n' and lastCharReceived != '\r')) {
            try doCommand();
        } else if (c != '\n') {
            if (terminalBufferTop < terminalBuffer.len) {
                terminalBuffer[terminalBufferTop] = c;
                terminalBufferTop += 1;
                // echo it back to them
                _ = imx.lpuart.lpuart1.writeChar(true, c);
            }
        }
        lastCharReceived = c;
    }
}

pub fn registerCommand(comptime name: []const u8, comptime cmd: CommandFunc) !void {
    var g = try registeredCommands.getOrPut(name);
    if (g.found_existing) return error.CommandNameAlreadyUsed;
    g.value_ptr.* = &cmd;
}

fn helpCommand(_: []const []const u8) void {
    var writer = imx.lpuart.lpuart1.writer();
    writer.print("There is no help yet.\n", .{}) catch {};
}

pub fn task() !void {
    try registerCommand("help", helpCommand);

    putCommandPrompt();
    while (true) {
        try receiveChars();
    }
}
