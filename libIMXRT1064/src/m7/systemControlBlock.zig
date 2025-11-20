pub const ConfigurationAndControlRegister = packed struct(u32) {
    canEnterThreadModeWithExceptionsActive: bool,
    unprivilegedCanAccessSoftwareTriggeredInterruptRegister: bool,
    _pad0: bool,
    trapUnalignedWordAndHalfwordAccesses: bool,
    trapDivZero: bool,
    _pad1: u3,
    preciseDataAccessFaultBehaviourInHandlersWithPriorityMinusOneAndMinusTwo: enum(u1) {
        lockup = 0,
        ignore = 1,
    },
    exceptionEntryStackFrameAlignment: enum(u1) {
        fourBytes = 0,
        eightBytes = 1,
    },
    _pad2: u6,
    dataCacheEnable: bool,
    instructionCacheEnable: bool,
    branchPredictionEnabled: bool,
    _pad3: u13,
};

pub const CacheLevelIDRegister = packed struct(u32) {
    cacheTypePerLevel: [7]enum(u3) {
        noCache = 0,
        instructionCacheOnly = 1,
        dataCacheOnly = 2,
        separateInstructionAndDataCaches = 3,
        unifiedCache = 4,
    },
    levelOfUnificationInnerShareable: u3,
    levelOfCoherency: u3,
    levelOfUnificationUniprocessor: u3,
    _pad0: u2,
};

pub const CacheLineSizeInWords = enum(u3) {
    @"4" = @ctz(@as(usize, 4)) - 2,
    @"8" = @ctz(@as(usize, 8)) - 2,
    @"16" = @ctz(@as(usize, 16)) - 2,
    @"32" = @ctz(@as(usize, 32)) - 2,
    @"64" = @ctz(@as(usize, 64)) - 2,
    @"128" = @ctz(@as(usize, 128)) - 2,
    @"256" = @ctz(@as(usize, 256)) - 2,
    @"512" = @ctz(@as(usize, 512)) - 2,
};

pub const CacheTypeRegister = packed struct(u32) {
    smallestInstructionCacheLine: CacheLineSizeInWords,
    _pad0: u12,
    smallestDataCacheLine: CacheLineSizeInWords,
    // We could do something really fucked up with the comptime to generate these enums. But I won't.
    exclusivesReservationGranuleSizeInWords: enum(u4) {
        notProvidedAssume512Words = 0,
        @"2" = @ctz(@as(usize, 2)),
        @"4" = @ctz(@as(usize, 4)),
        @"8" = @ctz(@as(usize, 8)),
        @"16" = @ctz(@as(usize, 16)),
        @"32" = @ctz(@as(usize, 32)),
        @"64" = @ctz(@as(usize, 64)),
        @"128" = @ctz(@as(usize, 128)),
        @"256" = @ctz(@as(usize, 256)),
        @"512" = @ctz(@as(usize, 512)),
    },
    cacheWriteBackGranuleSizeInWords: enum(u4) {
        notProvidedAssume512WordsOrMaxCacheLineSizeInCacheSizeIDRegister = 0,
        @"2" = @ctz(@as(usize, 2)),
        @"4" = @ctz(@as(usize, 4)),
        @"8" = @ctz(@as(usize, 8)),
        @"16" = @ctz(@as(usize, 16)),
        @"32" = @ctz(@as(usize, 32)),
        @"64" = @ctz(@as(usize, 64)),
        @"128" = @ctz(@as(usize, 128)),
        @"256" = @ctz(@as(usize, 256)),
        @"512" = @ctz(@as(usize, 512)),
    },
    _pad1: u1,
    format: enum(u3) {
        noCache = 0,
        armv7 = 4,
    },
};

pub const CacheSizeIDRegister = packed struct(u32) {
    cacheLineSizeInWords: CacheLineSizeInWords,
    associativityMinusOne: u10,
    numSetsMinusOne: u15,
    supportFlags: packed struct(u4) {
        writeAllocation: bool,
        readAllocation: bool,
        writeBack: bool,
        writeThrough: bool,
    },
};

pub const CacheSizeSelectionRegister = packed struct(u32) {
    isInstructionOrDataCache: enum(u1) {
        dataOrUnified = 0,
        instruction = 1,
    },
    cacheLevel: enum(u3) {
        level1 = 0,
        level2 = 1,
        level3 = 2,
        level4 = 3,
        level5 = 4,
        level6 = 5,
        level7 = 6,
    },
    _pad0: u28,
};

pub const SystemHandlerPriorityRegister = packed struct(u96) {
    debugMonitor: u8,
    _pad0: u8,
    pendSV: u8,
    sysTick: u8,
    _pad1: u8,
    _pad2: u8,
    _pad3: u8,
    svCall: u8,
    memManage: u8,
    busFault: u8,
    usageFault: u8,
    _pad4: u8,
};

pub const configurationAndControlRegister: *volatile ConfigurationAndControlRegister = @ptrFromInt(0xE000ED14);
pub const cacheLevelIDRegister: *const volatile CacheLevelIDRegister = @ptrFromInt(0xE000ED78); // Value read depends on what's in cacheSizeSelectionRegister!
pub const cacheTypeRegister: *const volatile CacheTypeRegister = @ptrFromInt(0xE000ED7C); // Value read depends on what's in cacheSizeSelectionRegister!
pub const cacheSizeIDRegister: *const volatile CacheSizeIDRegister = @ptrFromInt(0xE000ED80); // Value read depends on what's in cacheSizeSelectionRegister!
pub const cacheSizeSelectionRegister: *volatile CacheSizeSelectionRegister = @ptrFromInt(0xE000ED84);
pub const systemHandlerPriorityRegister: *volatile SystemHandlerPriorityRegister = @ptrFromInt(0xE000ED18);
