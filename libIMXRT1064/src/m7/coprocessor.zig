const CoprocessorAccessControlRegister = packed struct(u32) {
    _pad0: u19,
    ctrl: enum(u2) {
        noAccess = 0,
        privilegedOnly = 1,
        fullAccess = 3,
    },
    _pad1: u11,
};

pub const coprocessorAccessControlRegister: *volatile CoprocessorAccessControlRegister = @ptrFromInt(0xE000ED88);
