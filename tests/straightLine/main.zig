const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Core = @import("lang/core.zig");

pub fn main() !void {
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const outw: std.fs.File.Writer = std.io.getStdOut().writer();

    Core.ProductionActions.initOutWriter(outw);
    Core.SymbolActions.initSymbolTable(allocator);
    defer Core.SymbolActions.deinitSymbolTable();

    const num_result: anyerror!Core.SemanticData = Core.Compiler.compileFile("test.txt", allocator);

    if (num_result) |result| {
        try outw.print("{d:.2}\n", .{result});
    } else |e| {
        try outw.print("{any}\n", .{e});
    }
}

test "Compile Files" {
    var tempOutDir = std.testing.tmpDir(.{});
    var inFileDir = try std.fs.cwd().openDir("tests/straightLine/inputs", .{ .iterate = true });
    var expectedDir = try std.fs.cwd().openDir("tests/straightLine/expected", .{ .iterate = true });
    var inIterator = inFileDir.iterate();
    // Arena can be used for all the junk that we do in only straight line.
    // Testing should be used in all calls into zacc so that we can detect leaks there
    var arena = ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const arenaAllocator = arena.allocator();

    while (inIterator.next()) |optEntry| {
        if (optEntry) |entry| {
            if (entry.kind != .file)
                continue;

            const inFile = try inFileDir.openFile(entry.name, .{ .mode = .read_only });
            const outFile = try tempOutDir.dir.createFile(entry.name, .{ .read = true });
            const expectedFile = try expectedDir.openFile(entry.name, .{ .mode = .read_only });

            Core.ProductionActions.initOutWriter(outFile.writer());
            Core.SymbolActions.initSymbolTable(arenaAllocator);
            defer Core.SymbolActions.deinitSymbolTable();

            _ = try Core.Compiler.compileStdFsFile(inFile, std.testing.allocator);

            inFile.close();
            try outFile.seekTo(0);
            const outBuff = try outFile.readToEndAlloc(arenaAllocator, 256);
            const expectedBuff = try expectedFile.readToEndAlloc(arenaAllocator, 256);
            if (!std.mem.eql(u8, outBuff, expectedBuff)) {
                std.debug.print("Inequality in file: {s}\n", .{entry.name});
                std.debug.print("    Lengths: {d}, {d}\n", .{ outBuff.len, expectedBuff.len });
                for (outBuff, 0..) |c1, i| {
                    var c2: u8 = undefined;
                    if (i >= expectedBuff.len) {
                        c2 = '$';
                    } else {
                        c2 = expectedBuff[i];
                    }
                    if (c1 != c2) {
                        std.debug.print("    MISMATCH: {c} vs {c}\n", .{ c1, c2 });
                    }
                }
                if (expectedBuff.len > outBuff.len) {
                    for (outBuff.len..expectedBuff.len) |i| {
                        std.debug.print("    MISMATCH: $ vs {c}\n", .{expectedBuff[i]});
                    }
                }
            }
        } else {
            break;
        }
    } else |err| {
        std.debug.print("Failed to iterate input dir with error: {any}\n", .{err});
    }
}
