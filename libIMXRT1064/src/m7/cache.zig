const systemControlBlock = @import("systemControlBlock.zig");

const CACHE_LINE_SIZE = 32;

// Writing something to the below registers triggers their respective operation.

// Instruction cache invalidate all. Write anything you want.
const instructionCacheInvalidateAll: *volatile bool = @ptrFromInt(0xE000EF50);

// Instruction cache invalidate by address. Expects a CACHE_LINE_SIZE aligned address.
const instructionCacheInvalidateByAddress: *volatile usize = @ptrFromInt(0xE000EF58);

// Invalidate/clean data cache by address. Expects a CACHE_LINE_SIZE aligned address.
const dataCacheInvalidateByAddress: *volatile usize = @ptrFromInt(0xE000EF5C);
const dataCacheCleanByAddress: *volatile usize = @ptrFromInt(0xE000EF68);
const dataCacheCleanAndInvalidateByAddress: *volatile usize = @ptrFromInt(0xE000EF70);

// Invalidate/clean data cache by Set/Way
// The bits in here depend on the cache size ID register for the selected cache. See the SetWayOperationInfo struct below.
const DataCacheOperationBySetWayRegister = packed struct(u32) {
    _pad0: u5 = 0,
    setIndex: u7,
    _pad1: u18 = 0,
    wayIndex: u2,
};
const dataCacheInvalidateBySetWay: *volatile DataCacheOperationBySetWayRegister = @ptrFromInt(0xE000EF60);
const dataCacheCleanBySetWay: *volatile DataCacheOperationBySetWayRegister = @ptrFromInt(0xE000EF6C);
const dataCacheCleanAndInvalidateBySetWay: *volatile DataCacheOperationBySetWayRegister = @ptrFromInt(0xE000EF74);

// Generator for *ByAddress functions, which all do the same thing just with a different register.
fn OperationByAddress(comptime register: *volatile usize) fn (*align(CACHE_LINE_SIZE) anyopaque, size: usize) void {
    return struct {
        fn doOperation(addr: *align(CACHE_LINE_SIZE) anyopaque, size: usize) void {
            @setRuntimeSafety(false);

            const ad = @intFromPtr(addr);
            const sz = size & ~(@as(usize, CACHE_LINE_SIZE) - 1);

            // I don't like this, we should have a dsb and isb after the whole loop, but I don't know how to do that in Zig.
            for (0..sz / CACHE_LINE_SIZE) |i| {
                @atomicStore(usize, register, ad + (i * CACHE_LINE_SIZE), .seq_cst);
            }
        }
    }.doOperation;
}

// Generator for *DCache functions, which all do the same thing just with a different register.
fn OperationOnWholeDCache(comptime register: *volatile DataCacheOperationBySetWayRegister) fn () void {
    return struct {
        fn doOperation() void {
            var cssr = systemControlBlock.cacheSizeSelectionRegister.*;
            cssr.isInstructionOrDataCache = .dataOrUnified;
            cssr.cacheLevel = .level1;
            @atomicStore(systemControlBlock.CacheSizeSelectionRegister, systemControlBlock.cacheSizeSelectionRegister, cssr, .seq_cst);

            const cacheLevelSize = systemControlBlock.cacheSizeIDRegister.*;

            var setIndex: u7 = @truncate(cacheLevelSize.numSetsMinusOne);
            while (setIndex != 0) {
                var wayIndex: u2 = @truncate(cacheLevelSize.associativityMinusOne);
                while (wayIndex != 0) {
                    @atomicStore(DataCacheOperationBySetWayRegister, register, .{
                        .setIndex = setIndex,
                        .wayIndex = wayIndex,
                    }, .seq_cst);
                    wayIndex -= 1;
                }
                setIndex -= 1;
            }
        }
    }.doOperation;
}

// Enable and disable I/D cache.
pub fn enableICache() void {
    if (systemControlBlock.configurationAndControlRegister.instructionCacheEnable) return;

    @atomicStore(bool, instructionCacheInvalidateAll, true, .seq_cst);
    var ccar = systemControlBlock.configurationAndControlRegister.*;
    ccar.instructionCacheEnable = true;
    @atomicStore(systemControlBlock.ConfigurationAndControlRegister, systemControlBlock.configurationAndControlRegister, ccar, .seq_cst);
}

pub fn disableICache() void {
    if (!systemControlBlock.configurationAndControlRegister.instructionCacheEnable) return;

    var ccar = systemControlBlock.configurationAndControlRegister.*;
    ccar.instructionCacheEnable = false;
    @atomicStore(systemControlBlock.ConfigurationAndControlRegister, systemControlBlock.configurationAndControlRegister, ccar, .seq_cst);
    @atomicStore(bool, instructionCacheInvalidateAll, true, .seq_cst);
}

pub fn enableDCache() void {
    if (systemControlBlock.configurationAndControlRegister.dataCacheEnable) return;

    invalidateDCache();

    var ccar = systemControlBlock.configurationAndControlRegister.*;
    ccar.dataCacheEnable = true;
    @atomicStore(systemControlBlock.ConfigurationAndControlRegister, systemControlBlock.configurationAndControlRegister, ccar, .seq_cst);
}

pub fn disableDCache() void {
    if (!systemControlBlock.configurationAndControlRegister.dataCacheEnable) return;

    var ccar = systemControlBlock.configurationAndControlRegister.*;
    ccar.dataCacheEnable = false;
    @atomicStore(systemControlBlock.ConfigurationAndControlRegister, systemControlBlock.configurationAndControlRegister, ccar, .seq_cst);

    invalidateDCache();
}

// Invalidate the entire icache
pub fn invalidateICache() void {
    @atomicStore(bool, instructionCacheInvalidateAll, true, .seq_cst);
}

// Invalidate/clean entire dcache
pub const invalidateDCache = OperationOnWholeDCache(dataCacheInvalidateBySetWay);
pub const cleanDCache = OperationOnWholeDCache(dataCacheCleanBySetWay);
pub const cleanInvalidateDCache = OperationOnWholeDCache(dataCacheCleanAndInvalidateBySetWay);

// Invalidate/clean by address
pub const invalidateICacheByAddr = OperationByAddress(instructionCacheInvalidateByAddress);
pub const invalidateDCacheByAddr = OperationByAddress(dataCacheInvalidateByAddress);
pub const cleanDCacheByAddr = OperationByAddress(dataCacheCleanByAddress);
pub const cleanInvalidateDCacheByAddr = OperationByAddress(dataCacheCleanAndInvalidateByAddress);
