const specificationGenerator = @import("compilerLib");
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

const SemanticData = union(enum) {
    num: f64,
    id: []const u8,
    none: void,
};

const grammar: []const Production = &[_]Production{
    .{ .rule = "PROGRAM -> SPRIME EOF", .semanticAction = undefined },
    .{ .rule = "SPRIME -> S SEMICOLON", .semanticAction = undefined },
    .{ .rule = "SPRIME -> SPRIME S SEMICOLON", .semanticAction = undefined },
    .{ .rule = "S -> ID L_ASSIGN E", .semanticAction = undefined },
    .{ .rule = "S -> E R_ASSIGN ID", .semanticAction = undefined },
    .{ .rule = "E -> E PLUS T", .semanticAction = undefined },
    .{ .rule = "E -> T", .semanticAction = undefined },
    .{ .rule = "T -> T MULT F", .semanticAction = undefined },
    .{ .rule = "T -> T DIV F", .semanticAction = undefined },
    .{ .rule = "T -> F", .semanticAction = undefined },
    .{ .rule = "F -> ID", .semanticAction = undefined },
    .{ .rule = "F -> NUM", .semanticAction = undefined },
    .{ .rule = "F -> L_PAREN E R_PAREN", .semanticAction = undefined },
};

const Token = specificationGenerator.Token(TokenKind);

const Production = Token.Production(SemanticData);

const Specification = Production.CreateSpecification(grammar);

test "printProds" {
    @setEvalBranchQuota(100000);
    print("AAAH\n", .{});
    for (Specification.grammar) |prod| {
        prod.debugPrint();
        print("\n", .{});
    }
}
