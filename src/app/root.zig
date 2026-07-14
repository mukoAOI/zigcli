//! App package facade — high-level declarative CLI API.

const app_mod = @import("app.zig");
const bind_mod = @import("bind.zig");
const check_mod = @import("check.zig");

pub const App = app_mod.App;
pub const Command = app_mod.Command;
pub const AppError = app_mod.AppError;
pub const AppAllocError = app_mod.AppAllocError;
pub const AppCheckedError = app_mod.AppCheckedError;
pub const BindError = bind_mod.BindError;
pub const BindAllocError = bind_mod.BindAllocError;
pub const bindConfig = bind_mod.bindConfig;
pub const bindConfigAlloc = bind_mod.bindConfigAlloc;
pub const validateConfig = check_mod.validateConfig;

test {
    _ = bind_mod;
    _ = app_mod;
    _ = check_mod;
}
