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
    try stdioWriter.flush();
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
            _ = try stdioWriter.writeAll(&b);
            try stdioWriter.flush();
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

// Fields of the struct in the array should be scalars. Any \n or \t in the format output will break it...
fn writeArrayAsTable(arr: anytype) !void {
    const rowTypeInfo = @typeInfo(@typeInfo(@TypeOf(arr)).array.child).@"struct";
    var columnWidths: [rowTypeInfo.fields.len]u32 = @splat(0);
    inline for (rowTypeInfo.fields, 0..) |columnField, columnIndex| {
        columnWidths[columnIndex] = columnField.name.len + 2; // +2 for a space on either side...
        for (arr) |rowValue| {
            const fieldValue = @field(rowValue, columnField.name);
            columnWidths[columnIndex] = @max(columnWidths[columnIndex], std.fmt.count("{}", .{fieldValue}) + 2);
        }
    }

    for (columnWidths) |w| {
        // +1 for the | on either side of a column
        for (0..w + 1) |_| {
            _ = try stdioWriter.write("-");
        }
    }

    _ = try stdioWriter.write("-\n");

    inline for (rowTypeInfo.fields, 0..) |columnField, columnIndex| {
        // Print column separator and a space for the value
        _ = try stdioWriter.write("| ");
        // Figure out how long the value is, +1 for the space we just added.
        const amtWritten = columnField.name.len + 1;
        // Print the name of the field
        _ = try stdioWriter.write(columnField.name);
        // pad with spaces
        for (amtWritten..columnWidths[columnIndex]) |_| {
            _ = try stdioWriter.write(" ");
        }
    }

    _ = try stdioWriter.write("|\n");

    for (columnWidths) |w| {
        // +1 for the | on either side of a column
        for (0..w + 1) |_| {
            _ = try stdioWriter.write("-");
        }
    }

    _ = try stdioWriter.write("-\n");

    for (arr) |rowValue| {
        inline for (rowTypeInfo.fields, 0..) |columnField, columnIndex| {
            // Print column separator and a space for the value
            _ = try stdioWriter.write("| ");
            // Figure out how long the value is, +1 for the space we just added.
            const amtWritten = std.fmt.count("{}", .{@field(rowValue, columnField.name)}) + 1;
            // Print the value itself
            try stdioWriter.print("{}", .{@field(rowValue, columnField.name)});
            // pad with spaces
            for (amtWritten..columnWidths[columnIndex]) |_| {
                _ = try stdioWriter.write(" ");
            }
        }
        // End the row
        _ = try stdioWriter.write("|\n");
    }

    for (columnWidths) |w| {
        // +2 for the | on either side of a column
        for (0..w + 1) |_| {
            _ = try stdioWriter.write("-");
        }
    }

    _ = try stdioWriter.write("-\n");

    try stdioWriter.flush();
}

const splatBytes: [4096]u8 = @splat('A');
fn testSplatCommand(_: []const []const u8) void {
    stdioWriter.flush() catch {};

    const before = client.readPerformanceCounter();

    // Call write directly to bypass writer overhead
    _ = client.write(0, &splatBytes);

    const now = client.readPerformanceCounter();
    const delta = if (now >= before) now - before else now + (0xFFFFFFFF - before);
    const deltaMs = delta / (client.getPerformanceCounterFrequencyHz() / 1_000);
    stdioWriter.print("\nThat was {} bytes. It took us {}ms (from process perspective)\n", .{ splatBytes.len, deltaMs }) catch {};
}

const TestWaitResult = struct {
    expectedMs: u32 = 0,
    actualMs: u32 = 0,
    successful: bool = false,
};

fn testWait(ms: u32) !TestWaitResult {
    _ = try stdioWriter.print("Testing wait of {}ms\n", .{ms});
    try stdioWriter.flush();

    const before = client.readPerformanceCounter();
    client.sleep(ms);
    const now = client.readPerformanceCounter();
    const delta = if (now >= before) now - before else now + (0xFFFFFFFF - before);
    const deltaMs = delta / (client.getPerformanceCounterFrequencyHz() / 1_000);

    return .{
        .expectedMs = ms,
        .actualMs = deltaMs,
        .successful = true,
    };
}

fn testWaitCommand(_: []const []const u8) void {
    _ = stdioWriter.write("Please wait...\n") catch {};

    const results: [6]TestWaitResult = .{
        testWait(1) catch .{},
        testWait(5) catch .{},
        testWait(10) catch .{},
        testWait(100) catch .{},
        testWait(500) catch .{},
        testWait(1000) catch .{},
    };

    writeArrayAsTable(results) catch {};
}

var stdioWriterBuffer: [1024]u8 = undefined;
pub fn task() !void {
    stdioWriter = client.stdioWriter();
    stdioWriter.buffer = &stdioWriterBuffer;

    try registerCommand("testSplat", testSplatCommand);
    try registerCommand("testWait", testWaitCommand);
    try registerCommand("help", helpCommand);

    try putCommandPrompt();
    try stdioWriter.flush();

    while (true) {
        try receiveChars();
    }
}
