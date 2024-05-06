const std = @import("std");
const print = std.debug.print;

pub const TokenType = enum(u8) {
    EOF,
    ID,
    L_ASSIGN,
    R_ASSIGN,
    NUM,
    PLUS,
    MULT,
    DIV,
    LPAREN,
    RPAREN,
    SEMICOLON,
    NOTOKEN,

    pub fn getRegex(self: TokenType) [:0]const u8 {
        return switch (self) {
            .EOF => "",
            .ID => "[a-zA-Z_][a-zA-Z_0-9]*",
            .L_ASSIGN => "<-",
            .R_ASSIGN => "->",
            .NUM => "-?[0-9]+(.[0-9]*)?",
            .PLUS => "\\+",
            .MULT => "\\*",
            .DIV => "/",
            .LPAREN => "\\(",
            .RPAREN => "\\)",
            .SEMICOLON => ";",
            .NOTOKEN => "",
        };
    }
};

pub const Token = union(TokenType) { EOF: void, ID: [:0]const u8, L_ASSIGN: void, R_ASSIGN: void, NUM: f32, PLUS: void, MULT: void, DIV: void, LPAREN: void, RPAREN: void, SEMICOLON: void, NOTOKEN: void };

pub const SymbolClass = enum {
    Terminal,
    NonTerminal,
};

pub const NonTerminalSymbol = enum {
    SPRIME,
    S,
    E,
    V,
    F,
    T,
};

pub const Symbol = union(SymbolClass) {
    Terminal: TokenType,
    NonTerminal: NonTerminalSymbol,
};

pub const Production = struct {
    LHS: NonTerminalSymbol,
    RHS: []const Symbol,

    pub fn debugPrint(self: Production) void {
        print("{s} ->", .{@tagName(self.LHS)});
        for (self.RHS) |symb| {
            print(" {s}", .{switch (symb) {
                .NonTerminal => |nonTermSymb| @tagName(nonTermSymb),
                .Terminal => |termSymb| @tagName(termSymb),
            }});
        }
    }
};

const sym: Symbol = {
    .T;
};

pub const grammar = [_]Production{
    Production{
        .LHS = .SPRIME,
        .RHS = &[_]Symbol{ .{ .NonTerminal = .S }, .{ .Terminal = .EOF } },
    },
    Production{ .LHS = .S, .RHS = &[_]Symbol{
        .{ .NonTerminal = .S },
        .{ .Terminal = .SEMICOLON },
        .{ .NonTerminal = .S },
    } },
    Production{ .LHS = .S, .RHS = &[_]Symbol{
        .{ .Terminal = .ID },
        .{ .Terminal = .L_ASSIGN },
        .{ .NonTerminal = .E },
    } },
    Production{ .LHS = .S, .RHS = &[_]Symbol{
        .{ .NonTerminal = .E },
        .{ .Terminal = .R_ASSIGN },
        .{ .Terminal = .ID },
    } },
    Production{ .LHS = .E, .RHS = &[_]Symbol{
        .{ .NonTerminal = .E },
        .{ .Terminal = .PLUS },
        .{ .NonTerminal = .T },
    } },
    Production{ .LHS = .E, .RHS = &[_]Symbol{
        .{ .NonTerminal = .T },
    } },
    Production{ .LHS = .T, .RHS = &[_]Symbol{
        .{ .NonTerminal = .T },
        .{ .Terminal = .MULT },
        .{ .NonTerminal = .F },
    } },
    Production{ .LHS = .T, .RHS = &[_]Symbol{
        .{ .NonTerminal = .T },
        .{ .Terminal = .DIV },
        .{ .NonTerminal = .F },
    } },
    Production{ .LHS = .T, .RHS = &[_]Symbol{
        .{ .NonTerminal = .F },
    } },
    Production{ .LHS = .F, .RHS = &[_]Symbol{
        .{ .Terminal = .ID },
    } },
    Production{ .LHS = .F, .RHS = &[_]Symbol{
        .{ .Terminal = .NUM },
    } },
    Production{ .LHS = .F, .RHS = &[_]Symbol{
        .{ .Terminal = .LPAREN },
    } },
};

test "printProds" {
    print("AAAH\n", .{});
    for (grammar) |prod| {
        prod.debugPrint();
        print("\n", .{});
    }
}
