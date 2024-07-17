const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Core = @import("lang/core.zig");

pub fn main() !void {
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const outw = std.io.getStdOut().writer();

    const AST_result: anyerror!Core.SemanticData = Core.Compiler.compileFileWithOpts("test.txt", allocator, false, false);

    if (AST_result) |result| {
        try outw.print("{s}\n", .{@tagName(result)});
    } else |e| {
        try outw.print("{any}\n", .{e});
    }
}
