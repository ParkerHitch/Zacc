const std = @import("std");
const compilerGenerator = @import("compilerLib");
const specificationGenerator = compilerGenerator.specificationGenerator;
const print = @import("std").debug.print;

const TokenKind = enum {
    EOF,
    PRINT,
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
            .PRINT => "print",
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

pub const ProductionActions = @import("actions/productionActions.zig");
pub const OperatorActions = @import("actions/operatorActions.zig");
pub const SymbolActions = @import("actions/symbolActions.zig");

pub const SemanticData = f64;

const grammar: []const Production = &[_]Production{
    .{ .rule = "PROGRAM -> SPRIME EOF", .semanticAction = ProductionActions.doNothing },
    .{ .rule = "SPRIME -> S SEMICOLON", .semanticAction = ProductionActions.doNothing },
    .{ .rule = "SPRIME -> SPRIME S SEMICOLON", .semanticAction = ProductionActions.doNothing },
    .{ .rule = "S -> PRINT L_PAREN E R_PAREN", .semanticAction = ProductionActions.print },
    .{ .rule = "S -> ID L_ASSIGN E", .semanticAction = SymbolActions.leftAssignVariable },
    .{ .rule = "S -> E R_ASSIGN ID", .semanticAction = SymbolActions.rightAssignVariable },
    .{ .rule = "E -> E PLUS T", .semanticAction = OperatorActions.add },
    .{ .rule = "E -> E MINUS T", .semanticAction = OperatorActions.sub },
    .{ .rule = "E -> T", .semanticAction = ProductionActions.percolateFloat },
    .{ .rule = "T -> T MULT F", .semanticAction = OperatorActions.mul },
    .{ .rule = "T -> T DIV F", .semanticAction = OperatorActions.div },
    .{ .rule = "T -> F", .semanticAction = ProductionActions.percolateFloat },
    .{ .rule = "F -> ID", .semanticAction = SymbolActions.fetchValue },
    .{ .rule = "F -> NUM", .semanticAction = ProductionActions.parseFloat },
    .{ .rule = "F -> MINUS NUM", .semanticAction = OperatorActions.negate },
    .{ .rule = "F -> L_PAREN E R_PAREN", .semanticAction = ProductionActions.percolateFloatParens },
};

const Token = specificationGenerator.Token(TokenKind);

const Production = Token.Production(SemanticData);

pub const SymbolData: type = Production.SymbolData;

pub const Specification = Production.CreateSpecification(grammar);

pub const Compiler = compilerGenerator.Compiler(Specification);

fn printInput(rhs: []SymbolData) SemanticData {
    for (rhs) |symbolData| {
        switch (symbolData) {
            .token => |tok| print("{s} ", .{@tagName(tok.kind)}),
            .semanticData => |semd| print("{d:.2} ", .{semd}),
        }
    }
    print("\n", .{});
    return 0;
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
