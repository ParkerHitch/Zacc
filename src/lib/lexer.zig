const spec = @import("../lang/specification.zig");
const Token = spec.Token;
const TokenType = spec.TokenType;
const std = @import("std");
const automata = @import("regexParser.zig").specNodalDFA;
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const FileReader = File.Reader;
const StringHashMap = std.hash_map.StringHashMap(void);
const print = std.debug.print;

const TokenList = std.ArrayList(Token);

const LexingError = error{ UNEXPECTED_WHITESPACE, INVALID_SYNTAX };

pub fn lexFile(reader: *WholeFileBufferReader, allocator: Allocator) ![]Token {
    var outArr: TokenList = TokenList.init(allocator);
    defer outArr.deinit();

    var automataState: usize = 0;
    var charLoc: usize = 0;
    var firstCharLoc: usize = 0;
    var lastMatchLoc: ?usize = null;
    var lastMatchTok: ?TokenType = null;

    while (reader.getNextChar()) |byte| : (charLoc += 1) {
        if (byte == 0) {
            try outArr.append(Token{ .EOF = {} });
            break;
        }
        print("Reading: {c} @ {}\n", .{ byte, charLoc });
        if (isWhitespace(byte)) {
            if (automataState == 0) {
                firstCharLoc = charLoc + 1;
                continue;
            }
            if (automata.getAccepting(automataState)) |token| {
                try outArr.append(token.lexFromString(reader.buffer[firstCharLoc..charLoc]));

                print("Accepted: {}\n", .{token});
                print("    {s} - {}\n", .{ reader.buffer[firstCharLoc..charLoc], charLoc - firstCharLoc });
                automataState = 0;
                firstCharLoc = charLoc + 1;
            } else {
                return LexingError.UNEXPECTED_WHITESPACE;
            }
        } else {
            if (automata.nextState(automataState, byte)) |newState| {
                automataState = newState;
                if (automata.getAccepting(automataState)) |tok| {
                    lastMatchLoc = charLoc;
                    lastMatchTok = tok;
                }
            } else {
                // We have encountered an invalid transition. That means return the last time we were accepting.
                if (lastMatchLoc) |lastLoc| {
                    charLoc = lastLoc; // No +1 since it's gonna get incremented at end of loop
                    try reader.goBackTo(lastLoc + 1);

                    const outToken: Token = (lastMatchTok orelse unreachable)
                        .lexFromString(reader.buffer[firstCharLoc .. lastLoc + 1]);

                    try outArr.append(outToken);

                    print("Accepted: {}\n", .{lastMatchTok orelse unreachable});
                    print("    {s} - {}\n", .{ reader.buffer[firstCharLoc .. lastLoc + 1], lastLoc + 1 - firstCharLoc });

                    firstCharLoc = lastLoc + 1;
                    automataState = 0;
                    lastMatchLoc = null;
                    lastMatchTok = null;
                } else {
                    // Encountered an invalid transition before encountering a match. Error
                    return LexingError.INVALID_SYNTAX;
                }
            }
        }
    } else {
        try outArr.append(Token{ .EOF = {} });
    }

    const outSlice = outArr.toOwnedSlice();

    return outSlice;
}

fn isWhitespace(char: u8) bool {
    return char == ' ' or char == '\n' or char == '\t';
}

pub const WholeFileBufferReader = struct {
    const one_mb = (1 << 10) << 10;
    const maxFilesize = one_mb * 3;

    pub const WholeFileBufferError = error{ INVALID_SEEK_DEST, FILE_TOO_LARGE };

    location: usize = 0,
    buffer: []const u8,
    allocator: Allocator,

    pub fn init(inFile: File, allocator: Allocator) !@This() {
        var newOut: @This() = .{
            .buffer = undefined,
            .allocator = allocator,
        };

        newOut.buffer = inFile.readToEndAlloc(allocator, maxFilesize) catch return WholeFileBufferError.FILE_TOO_LARGE;

        return newOut;
    }

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.buffer);
    }

    pub fn getNextChar(self: *@This()) ?u8 {
        if (self.location >= self.buffer.len)
            return null;
        const out: u8 = self.buffer[self.location];
        self.location += 1;
        return out;
    }

    pub fn goBackTo(self: *@This(), newLoc: usize) !void {
        if (newLoc > self.location) {
            return WholeFileBufferError.INVALID_SEEK_DEST;
        }
        self.location = newLoc;
    }
};

test "testLex" {
    const allocator = std.testing.allocator;

    const inFile: File = try std.fs.cwd().openFile("test.txt", .{ .mode = .read_only });
    defer inFile.close();

    var reader = try WholeFileBufferReader.init(inFile, allocator);
    defer reader.deinit();

    const lexed = try lexFile(&reader, allocator);
    for (lexed) |token| {
        print("{any}\n", .{token});
    }

    allocator.free(lexed);
}