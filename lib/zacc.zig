const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;

const regexParser = @import("regexParser.zig");
const LexerGeneration = @import("lexer.zig");
const ParserGeneration = @import("parser.zig");

pub const specificationGenerator = @import("specification.zig");

pub fn Compiler(Specification: type) type {
    return struct {
        const Lexer = LexerGeneration.Lexer(Specification);
        const Parser = ParserGeneration.Parser(Specification);
        const WholeFileBufferReader = LexerGeneration.WholeFileBufferReader;

        pub fn compileFile(filename: []const u8, allocator: Allocator) !Specification.SemanticDataType {
            return compileFileWithOpts(filename, allocator, false, false);
        }

        pub fn compileFileWithOpts(filename: []const u8, allocator: Allocator, comptime verboseLexing: bool, comptime verboseParsing: bool) !Specification.SemanticDataType {
            const inFile: File = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
            defer inFile.close();

            var reader = try WholeFileBufferReader.init(inFile, allocator);
            defer reader.deinit();

            const tokens = try Lexer.lexFile(&reader, allocator, verboseLexing);
            defer allocator.free(tokens);

            const parseResult = try Parser.parseStream(tokens, allocator, verboseParsing);

            return parseResult;
        }
    };
}

test "rahh" {
    const fakeSpec = struct {
        pub const SemanticDataType = union(enum) { none: void };
    };
    const comp = Compiler(fakeSpec);
    _ = try comp.compileFile("ajdskl", std.testing.allocator);
}
