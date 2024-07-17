//! Actions revolving around symbols (variables)
const Core = @import("../core.zig");
const SymbolData = Core.SymbolData;
const std = @import("std");
const Allocator = std.mem.Allocator;
const VariableTable = std.StringHashMap(f64);

var mainTable: VariableTable = undefined;

pub fn initSymbolTable(allocator: Allocator) void {
    mainTable = VariableTable.init(allocator);
}

pub fn deinitSymbolTable() void {
    mainTable.deinit();
}

pub fn leftAssignVariable(in: []SymbolData) f64 {
    return assignValue(in[0].token.src, in[2].semanticData);
}

pub fn rightAssignVariable(in: []SymbolData) f64 {
    return assignValue(in[2].token.src, in[0].semanticData);
}

pub fn assignValue(name: []const u8, val: f64) f64 {
    mainTable.put(name, val) catch unreachable;
    return val;
}

pub fn fetchValue(in: []SymbolData) f64 {
    return mainTable.get(in[0].token.src) orelse 0;
}
