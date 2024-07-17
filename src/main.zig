const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Core = @import("lang/core.zig");

pub fn main() !void {
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const outw: std.fs.File.Writer = std.io.getStdOut().writer();

    Core.ProductionActions.initStdout(outw);
    Core.SymbolActions.initSymbolTable(allocator);
    defer Core.SymbolActions.deinitSymbolTable();

    const num_result: anyerror!Core.SemanticData = Core.Compiler.compileFileWithOpts("test.txt", allocator, false, false);

    if (num_result) |result| {
        try outw.print("{d:.2}\n", .{result});
    } else |e| {
        try outw.print("{any}\n", .{e});
    }
}
