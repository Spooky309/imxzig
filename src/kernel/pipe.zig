const std = @import("std");

const heap = @import("heap.zig");

name: []const u8,
reader: std.Io.Reader,
writer: std.Io.Writer,

// StringHashMap? Need to figure out the memory usage of it first. This is fine for now.
var globalPipes: std.ArrayList(@This()) = .empty;

pub fn createGlobalPipe(name: []const u8, reader: std.Io.Reader, writer: std.Io.Writer) !void {
    try globalPipes.append(heap.allocator(), .{ .name = name, .reader = reader, .writer = writer });
}

pub fn getGlobalPipe(name: []const u8) ?@This() {
    for (globalPipes.items) |p| {
        if (std.mem.eql(u8, p.name, name)) return p;
    }
    return null;
}
