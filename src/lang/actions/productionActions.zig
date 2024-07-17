//! Actions that are specifically meant to assist with massaging data from productions into better data.
//! No actual computation is done here.
const Core = @import("../core.zig");
const SymbolData = Core.SymbolData;
const std = @import("std");
const fWriter = std.fs.File.Writer;

var outw: fWriter = undefined;

pub fn initStdout(writer: fWriter) void {
    outw = writer;
}

/// Takes in one float and returns it.
pub fn percolateFloat(in: []SymbolData) f64 {
    return in[0].semanticData;
}

/// Takes in one float (surrounded by parens) and returns it.
pub fn percolateFloatParens(in: []SymbolData) f64 {
    return in[1].semanticData;
}

/// Parses a NUM token to a float
pub fn parseFloat(in: []SymbolData) f64 {
    return std.fmt.parseFloat(f64, in[0].token.src) catch unreachable;
}

pub fn doNothing(_: []SymbolData) f64 {
    return 0;
}

pub fn print(in: []SymbolData) f64 {
    outw.print("PRINT: {d:.4}\n", .{in[2].semanticData}) catch unreachable;
    return 0;
}
