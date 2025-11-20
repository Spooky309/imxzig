const flexspi = @import("libIMXRT1064").flexspi;

const LookUpTableIndices = flexspi.LookUpTableIndices;

pub fn get() flexspi.LookUpTable {
    const ADDRESS_BITS = 24;
    const READ_DUMMY_CYCLES = 4;

    var arr: flexspi.LookUpTable = [_]flexspi.LookUpTableBlock{.{}} ** 16;

    // Zig has no designated initializers, so we have to clear the whole LookUpTable
    //  and then write the entries we want.
    //  Annoying, but I can't find a better way.
    arr[@intFromEnum(LookUpTableIndices.READ)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0xEB },
            .{ .opcode = .RADDR_SDR, .numPads = ._4Pad, .operand = ADDRESS_BITS },
        },
    };

    arr[@intFromEnum(LookUpTableIndices.READ)].entries[1] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .DUMMY_SDR, .numPads = ._4Pad, .operand = READ_DUMMY_CYCLES },
            .{ .opcode = .READ_SDR, .numPads = ._4Pad, .operand = 0x04 },
        },
    };

    arr[@intFromEnum(LookUpTableIndices.READSTATUS)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0x05 },
            .{ .opcode = .READ_SDR, .numPads = ._1Pad, .operand = 0x04 },
        },
    };

    arr[@intFromEnum(LookUpTableIndices.WRITESTATUS)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0x01 },
            .{ .opcode = .WRITE_SDR, .numPads = ._1Pad, .operand = 0x04 },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.WRITEENABLE)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0x06 },
            .{ .opcode = .STOP, .numPads = ._1Pad, .operand = 0 },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.ERASESECTOR)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0x20 },
            .{ .opcode = .RADDR_SDR, .numPads = ._1Pad, .operand = ADDRESS_BITS },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.READID)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0x9F },
            .{ .opcode = .READ_SDR, .numPads = ._1Pad, .operand = 0x04 },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.PAGEPROGRAM)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0x02 },
            .{ .opcode = .RADDR_SDR, .numPads = ._1Pad, .operand = ADDRESS_BITS },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.PAGEPROGRAM)].entries[1] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .WRITE_SDR, .numPads = ._1Pad, .operand = 0x04 },
            .{ .opcode = .STOP, .numPads = ._1Pad, .operand = 0 },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.SUSPENDERASE)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0x75 },
            .{ .opcode = .STOP, .numPads = ._1Pad, .operand = 0 },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.CHIPERASE)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0x60 },
            .{ .opcode = .STOP, .numPads = ._1Pad, .operand = 0 },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.ERASEBLOCK)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0xD8 },
            .{ .opcode = .RADDR_SDR, .numPads = ._1Pad, .operand = ADDRESS_BITS },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.READ_SFDP)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0x5A },
            .{ .opcode = .RADDR_SDR, .numPads = ._1Pad, .operand = ADDRESS_BITS },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.READ_SFDP)].entries[1] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .DUMMY_SDR, .numPads = ._4Pad, .operand = READ_DUMMY_CYCLES },
            .{ .opcode = .READ_SDR, .numPads = ._4Pad, .operand = 0x04 },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.RESUMEERASE)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._1Pad, .operand = 0x7A },
            .{ .opcode = .STOP, .numPads = ._1Pad, .operand = 0 },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.EXIT_NOCMD)].entries[0] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._4Pad, .operand = 0xFF },
            .{ .opcode = .CMD_SDR, .numPads = ._4Pad, .operand = 0xFF },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.EXIT_NOCMD)].entries[1] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._4Pad, .operand = 0xFF },
            .{ .opcode = .CMD_SDR, .numPads = ._4Pad, .operand = 0xFF },
        },
    };
    arr[@intFromEnum(LookUpTableIndices.EXIT_NOCMD)].entries[2] = flexspi.LookUpTableEntry{
        .operations = .{
            .{ .opcode = .CMD_SDR, .numPads = ._4Pad, .operand = 0xFF },
            .{ .opcode = .STOP, .numPads = ._1Pad, .operand = 0 },
        },
    };

    return arr;
}
