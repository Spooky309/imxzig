pub const LookUpTableIndices = enum(usize) {
    READ = 0,
    READSTATUS = 1,
    WRITESTATUS = 2,
    WRITEENABLE = 3,
    ERASESECTOR = 5,
    READID = 8,
    PAGEPROGRAM = 9,
    SUSPENDERASE = 10,
    CHIPERASE = 11,
    ERASEBLOCK = 12,
    READ_SFDP = 13,
    RESUMEERASE = 14,
    EXIT_NOCMD = 15,
};

pub const LookUpTableOpcode = enum(u6) {
    CMD_SDR = 0x01,
    CMD_DDR = 0x21,
    RADDR_SDR = 0x02,
    RADDR_DDR = 0x22,
    CADDR_SDR = 0x03,
    CADDR_DDR = 0x23,
    MODE1_SDR = 0x04,
    MODE1_DDR = 0x24,
    MODE2_SDR = 0x05,
    MODE2_DDR = 0x25,
    MODE4_SDR = 0x06,
    MODE4_DDR = 0x26,
    MODE8_SDR = 0x07,
    MODE8_DDR = 0x27,
    WRITE_SDR = 0x08,
    WRITE_DDR = 0x28,
    READ_SDR = 0x09,
    READ_DDR = 0x29,
    LEARN_SDR = 0x0A,
    LEARN_DDR = 0x2A,
    DATSZ_SDR = 0x0B,
    DATSZ_DDR = 0x2B,
    DUMMY_SDR = 0x0C,
    DUMMY_DDR = 0x2C,
    DUMMY_RWDS_SDR = 0x0D,
    DUMMY_RWDS_DDR = 0x2D,
    JMP_ON_CS = 0x1F,
    STOP = 0,
};

pub const LookUpTableOperation = packed struct(u16) {
    operand: u8 = 0,
    numPads: enum(u2) { _1Pad = 0, _2Pad = 1, _4Pad = 2 } = ._1Pad,
    opcode: LookUpTableOpcode = .STOP,
};

pub const LookUpTableEntry = extern struct {
    operations: [2]LookUpTableOperation = [_]LookUpTableOperation{.{}} ** 2,
};

pub const LookUpTableBlock = extern struct {
    entries: [4]LookUpTableEntry = [_]LookUpTableEntry{.{}} ** 4,
};

pub const LookUpTable = [16]LookUpTableBlock;

pub const LookUpTableSequence = extern struct {
    seqNum: u8 = 0,
    seqId: u8 = 0,
    _pad0: u16 = 0,
};
