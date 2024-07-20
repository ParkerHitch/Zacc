//! Actions that perform mathematical operations.
const Core = @import("../core.zig");
const SymbolData = Core.SymbolData;
const std = @import("std");

pub fn negate(in: []SymbolData) f64 {
    return -1 * in[1].semanticData;
}

pub fn add(in: []SymbolData) f64 {
    return in[0].semanticData + in[2].semanticData;
}

pub fn sub(in: []SymbolData) f64 {
    return in[0].semanticData - in[2].semanticData;
}

pub fn mul(in: []SymbolData) f64 {
    return in[0].semanticData * in[2].semanticData;
}

pub fn div(in: []SymbolData) f64 {
    return in[0].semanticData / in[2].semanticData;
}
