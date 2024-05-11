const spec = @import("specification.zig");
const Token = spec.TokenType;
const std = @import("std");
const automata = @import("regexParser.zig").specNodalDFA;
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const FileReader = File.Reader;
const print = std.debug.print;

const TokenList = std.ArrayList(Token);

const LexingError = error{ UNEXPECTED_WHITESPACE, INVALID_SYNTAX };

pub fn lexFile(fileName: [:0]const u8, allocator: Allocator) ![]Token {
    const inFile: File = try std.fs.cwd().openFile(fileName, .{ .mode = .read_only });
    defer inFile.close();
    const fReader = inFile.reader();
    var dReader = try DoubleBufReader.init(fReader);

    var outArr: TokenList = TokenList.init(allocator);
    defer outArr.deinit();

    var automataState: usize = 0;
    var charLoc: usize = 0;
    var lastMatchLoc: ?usize = null;
    var lastMatchTok: ?Token = null;

    while (dReader.getNextChar()) |byteOpt| : (charLoc += 1) {
        if (byteOpt) |byte| {
            if (byte == 0) {
                try outArr.append(Token.EOF);
                break;
            }
            print("Reading: {c}\n", .{byte});
            if (isWhitespace(byte)) {
                if (automataState == 0) continue;
                if (automata.getAccepting(automataState)) |token| {
                    try outArr.append(token);
                    print("Accepted: {}\n", .{token});
                    automataState = 0;
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
                        try dReader.goBackTo(lastLoc + 1);
                        try outArr.append(lastMatchTok orelse unreachable);
                        print("Accepted: {}\n", .{lastMatchTok orelse unreachable});
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
            try outArr.append(Token.EOF);
            break;
        }
    } else |e| {
        return e;
    }

    const outSlice = outArr.toOwnedSlice();

    return outSlice;
}

fn isWhitespace(char: u8) bool {
    return char == ' ' or char == '\n' or char == '\t';
}

const DoubleBufReader = struct {
    const bufSz = 4096;

    pub const DoubleBufReadError = error{
        INVALID_SEEK_DEST,
    };

    reader: FileReader,
    buf1: [bufSz]u8 = undefined,
    buf2: [bufSz]u8 = undefined,
    buf1Current: bool = true,
    isFirstBuf: bool = true,
    loc: usize = 0,
    first: usize = 0,
    last: usize = 0,

    fn init(reader: FileReader) !@This() {
        var newOut: @This() = .{
            .reader = reader,
        };
        newOut.last = try reader.read(newOut.buf1[0..]);
        return newOut;
    }

    fn getNextChar(self: *@This()) !?u8 {
        if (self.loc >= self.last) {
            const nextBytes = try self.reader.read((if (self.buf1Current) self.buf2 else self.buf1)[0..]);
            if (nextBytes == 0)
                return null;
            self.last += nextBytes;
            self.buf1Current = !self.buf1Current;
            const newBufInd: usize = self.loc / bufSz;
            self.first = bufSz * (newBufInd - 1);
        }
        const out: u8 = (if (self.buf1Current) self.buf1 else self.buf2)[self.loc % bufSz];
        self.loc += 1;
        return out;
    }

    fn goBackTo(self: *@This(), newLoc: usize) !void {
        if (newLoc < self.first or newLoc >= self.loc) {
            return DoubleBufReadError.INVALID_SEEK_DEST;
        }
        // const newBufInd: usize = newLoc / bufSz;
        // const oldBufInd: usize = self.loc / bufSz;
        // if(newBufInd < oldBufInd - 1){
        //     return DoubleBufReadError.INVALID_SEEK_DEST;
        // }
        self.loc = newLoc;
        // if(newBufInd < oldBufInd){
        //     self.buf1Current = !self.buf1Current;
        // }
    }
};

test "testLex" {
    const allocator = std.testing.allocator;

    const lexed = try lexFile("test.txt", allocator);
    for (lexed) |token| {
        print("{any}\n", .{token});
    }

    allocator.free(lexed);
}
