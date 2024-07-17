const std = @import("std");
const compilerGenerator = @import("compilerLib");
const specificationGenerator = compilerGenerator.specificationGenerator;
const print = @import("std").debug.print;

const TokenKind = enum {
    EOF,
    ID,
    L_ASSIGN,
    R_ASSIGN,
    NUM,
    PLUS,
    MINUS,
    MULT,
    DIV,
    L_PAREN,
    R_PAREN,
    SEMICOLON,
    NOTOKEN,

    pub fn getRegex(self: TokenKind) [:0]const u8 {
        return switch (self) {
            .EOF => "",
            .ID => "([a-zA-Z]|_)([a-zA-Z0-9]|_)*",
            .L_ASSIGN => "<-",
            .R_ASSIGN => "->",
            .NUM => "-?[0-9]+(.[0-9]*)?",
            .PLUS => "\\+",
            .MINUS => "-",
            .MULT => "\\*",
            .DIV => "/",
            .L_PAREN => "\\(",
            .R_PAREN => "\\)",
            .SEMICOLON => ";",
            .NOTOKEN => "",
        };
    }
};

pub const SemanticData = union(enum) {
    num: f64,
    id: []const u8,
    none: void,
};

const grammar: []const Production = &[_]Production{
    .{ .rule = "PROGRAM -> SPRIME EOF", .semanticAction = printInput },
    .{ .rule = "SPRIME -> S SEMICOLON", .semanticAction = printInput },
    .{ .rule = "SPRIME -> SPRIME S SEMICOLON", .semanticAction = printInput },
    .{ .rule = "S -> ID L_ASSIGN E", .semanticAction = printInput },
    .{ .rule = "S -> E R_ASSIGN ID", .semanticAction = printInput },
    .{ .rule = "E -> E PLUS T", .semanticAction = printInput },
    .{ .rule = "E -> T", .semanticAction = printInput },
    .{ .rule = "T -> T MULT F", .semanticAction = printInput },
    .{ .rule = "T -> T DIV F", .semanticAction = printInput },
    .{ .rule = "T -> F", .semanticAction = printInput },
    .{ .rule = "F -> ID", .semanticAction = printInput },
    .{ .rule = "F -> NUM", .semanticAction = printInput },
    .{ .rule = "F -> L_PAREN E R_PAREN", .semanticAction = printInput },
};

const Token = specificationGenerator.Token(TokenKind);

const Production = Token.Production(SemanticData);

pub const Specification = Production.CreateSpecification(grammar);

pub const Compiler = compilerGenerator.Compiler(Specification);

fn printInput(rhs: []Production.SymbolData) SemanticData {
    for (rhs) |symbolData| {
        switch (symbolData) {
            .token => |tok| print("{s} ", .{@tagName(tok.kind)}),
            .semanticData => |semd| print("{s} ", .{@tagName(semd)}),
        }
    }
    print("\n", .{});
    return .{ .none = {} };
}

test "printProds" {
    print("AAAH\n", .{});
    for (Specification.grammar) |prod| {
        prod.debugPrint();
        print("\n", .{});
    }
}

test "compileFile" {
    _ = try Compiler.compileFileWithOpts("test.txt", std.testing.allocator, false, false);
}
