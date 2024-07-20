const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;

const regexParser = @import("src/regexParser.zig");
const LexerGeneration = @import("src/lexer.zig");
const ParserGeneration = @import("src/parser.zig");

pub const specificationGenerator = @import("src/specification.zig");

pub fn Compiler(Specification: type) type {
    return struct {
        const Lexer = LexerGeneration.Lexer(Specification);
        const Parser = ParserGeneration.Parser(Specification);
        const WholeFileBufferReader = LexerGeneration.WholeFileBufferReader;

        pub fn compileFile(filename: []const u8, allocator: Allocator) !Specification.SemanticDataType {
            const inFile: File = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
            defer inFile.close();

            return compileStdFsFile(inFile, allocator);
        }

        pub fn compileStdFsFile(file: File, allocator: Allocator) !Specification.SemanticDataType {
            var reader = try WholeFileBufferReader.init(file, allocator);
            defer reader.deinit();

            const tokens = try Lexer.lexFile(&reader, allocator);
            defer allocator.free(tokens);

            const parseResult = try Parser.parseStream(tokens, allocator);

            return parseResult;
        }
    };
}

test "Unit Tests" {
    std.testing.refAllDecls(@This());
    // TODO: Get unit tests back in all the files in src
}
