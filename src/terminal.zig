const std = @import("std");

const client = @import("kernel.zig").client;

const Error = error{
    CommandNameAlreadyUsed,
};

const CommandFunc = fn (args: []const []const u8) void;

var stdioWriter: std.Io.Writer = undefined;

// 128b buffer for registering commands. You can just make this bigger if needed.
//  Maybe if we have a real allocator later on, we can
var registeredCommandsBuffer: [128]u8 = undefined;
var registeredCommandsAllocator = std.heap.FixedBufferAllocator.init(&registeredCommandsBuffer);
var registeredCommands = std.StringHashMap(*const CommandFunc).init(registeredCommandsAllocator.allocator());

var terminalBuffer: [256]u8 = undefined;
var terminalBufferTop: u32 = 0;
var lastCharReceived: u8 = 0;

fn putCommandPrompt() !void {
    _ = try stdioWriter.write("> ");
}

fn doCommand() !void {
    if (terminalBufferTop == 0) {
        _ = try stdioWriter.write("\n");
    } else {
        const cmd = terminalBuffer[0..terminalBufferTop];
        try stdioWriter.print("\n{s}\n", .{cmd});
        if (registeredCommands.get(cmd)) |c| {
            c(&.{});
        } else {
            _ = try stdioWriter.write("Unrecognized command\n");
        }
    }
    try putCommandPrompt();
    terminalBufferTop = 0;
}

fn receiveChars() !void {
    var b: [1]u8 = .{0};

    _ = client.read(0, &b);

    const c = b[0];

    if (c == '\r' or (c == '\n' and lastCharReceived != '\r')) {
        try doCommand();
    } else if (c != '\n') {
        if (terminalBufferTop < terminalBuffer.len) {
            terminalBuffer[terminalBufferTop] = c;
            terminalBufferTop += 1;
            // echo it back to them
            _ = try stdioWriter.write(&b);
        }
    }
    lastCharReceived = c;
}

pub fn registerCommand(comptime name: []const u8, comptime cmd: CommandFunc) !void {
    var g = try registeredCommands.getOrPut(name);
    if (g.found_existing) return error.CommandNameAlreadyUsed;
    g.value_ptr.* = &cmd;
}

fn helpCommand(_: []const []const u8) void {
    _ = stdioWriter.write("There is no help yet.\n") catch {};
}

fn testWait(ms: u32) !void {
    const before = client.readPerformanceCounter();
    client.sleep(ms);
    const now = client.readPerformanceCounter();
    const delta = if (now >= before) now - before else now + (0xFFFFFFFF - before);
    const deltaMs = delta / (client.getPerformanceCounterFrequencyHz() / 1_000);

    try stdioWriter.print("Expected:\t{}ms\tActual: {}ms\n", .{ ms, deltaMs });
}

const splatBytes: [4096]u8 = @splat('A');
fn testSplatCommand(_: []const []const u8) void {
    const before = client.readPerformanceCounter();
    _ = stdioWriter.write(&splatBytes) catch {};
    const now = client.readPerformanceCounter();
    const delta = if (now >= before) now - before else now + (0xFFFFFFFF - before);
    const deltaMs = delta / (client.getPerformanceCounterFrequencyHz() / 1_000);
    stdioWriter.print("\nThat was {} bytes. It took us {}ms (from process perspective)\n", .{ splatBytes.len, deltaMs }) catch {};
}

fn testWaitCommand(_: []const []const u8) void {
    _ = stdioWriter.write("Testing wait times\n") catch {};
    testWait(1) catch {};
    testWait(5) catch {};
    testWait(10) catch {};
    testWait(100) catch {};
    testWait(500) catch {};
    testWait(1000) catch {};
}

pub fn task() !void {
    stdioWriter = client.stdioWriter();

    try registerCommand("testSplat", testSplatCommand);
    try registerCommand("testWait", testWaitCommand);
    try registerCommand("help", helpCommand);

    try putCommandPrompt();
    while (true) {
        try receiveChars();
    }
}
