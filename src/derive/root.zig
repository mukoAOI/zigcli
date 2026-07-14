//! Derive package facade — comptime struct → Metadata.

const spec_mod = @import("spec.zig");
const shape_mod = @import("shape.zig");
const options_mod = @import("options.zig");

pub const FieldSpec = spec_mod.FieldSpec;
pub const fieldSpec = spec_mod.fieldSpec;
pub const CommandSpec = spec_mod.CommandSpec;
pub const commandSpec = spec_mod.commandSpec;

pub const TypeShape = shape_mod.TypeShape;
pub const shapeOf = shape_mod.shapeOf;

pub const OptionsArray = options_mod.OptionsArray;
pub const optionsFromStruct = options_mod.optionsFromStruct;
pub const ArgumentsArray = options_mod.ArgumentsArray;
pub const argumentsFromStruct = options_mod.argumentsFromStruct;
pub const subcommandCount = options_mod.subcommandCount;
pub const Derived = options_mod.Derived;

test {
    _ = spec_mod;
    _ = shape_mod;
    _ = options_mod;
}
