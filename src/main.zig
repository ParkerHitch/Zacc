const std = @import("std");
// const ArenaAllocator = std.heap.ArenaAllocator;
// const lexer = @import("lib/lexer.zig");
// const parser = @import("lib/parser.zig");

pub fn main() !void {
    std.debug.print("ASdA", .{});
    // var arena = ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    //
    // const allocator = arena.allocator();
    // const outw = std.io.getStdOut().writer();
    //
    // const inFile = try std.fs.cwd().openFile("test.txt", .{ .mode = .read_only });
    // defer inFile.close();
    //
    // var reader = try lexer.WholeFileBufferReader.init(inFile, allocator);
    // defer reader.deinit();
    //
    // const maybeLexed = lexer.lexFile(&reader, allocator);
    // const lexed = maybeLexed catch {
    //     _ = try outw.write("Cannot lex input file.\n");
    //     return;
    // };
    //
    // const validParse = try parser.parseStream(lexed, allocator);
    //
    // if (validParse) {
    //     try outw.print("Input file was parsed successfully!", .{});
    // } else {
    //     try outw.print("ERROR: Input file cannot be parsed", .{});
    // }
}
