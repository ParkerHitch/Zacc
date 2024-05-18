const std = @import("std");
const print = std.debug.print;

// NOTE!!! THE LAST ELEMENT MUST BE A NOTOKEN ELEMENT
pub const TokenType = enum(u16) {
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

    pub fn getRegex(self: TokenType) [:0]const u8 {
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

pub const Token = union(TokenType) { EOF: void, ID: [:0]const u8, L_ASSIGN: void, R_ASSIGN: void, NUM: f32, PLUS: void, MULT: void, DIV: void, L_PAREN: void, R_PAREN: void, SEMICOLON: void, NOTOKEN: void };

pub const SymbolClass = enum {
    Terminal,
    NonTerminal,
};

pub const NonTerminalSymbol = enum {
    PROGRAM,
    SPRIME,
    S,
    E,
    F,
    T,
};

pub const Symbol = union(SymbolClass) {
    Terminal: TokenType,
    NonTerminal: NonTerminalSymbol,

    pub fn eql(self: @This(), other: @This()) bool {
        return switch (self) {
            .Terminal => |tt| switch (other) {
                .Terminal => |tt2| tt == tt2,
                .NonTerminal => false,
            },
            .NonTerminal => |nts| switch (other) {
                .Terminal => false,
                .NonTerminal => |nts2| nts == nts2,
            },
        };
    }
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

pub const grammar = [_]Production{
    Production{
        .LHS = .PROGRAM,
        .RHS = &[_]Symbol{ .{ .NonTerminal = .SPRIME }, .{ .Terminal = .EOF } },
    },
    Production{
        .LHS = .SPRIME,
        .RHS = &[_]Symbol{ .{ .NonTerminal = .S }, .{ .Terminal = .SEMICOLON } },
    },
    Production{
        .LHS = .SPRIME,
        .RHS = &[_]Symbol{ .{ .NonTerminal = .SPRIME }, .{ .NonTerminal = .S }, .{ .Terminal = .SEMICOLON } },
    },
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
        .{ .Terminal = .L_PAREN },
        .{ .NonTerminal = .E },
        .{ .Terminal = .R_PAREN },
    } },
    // Production{ .LHS = .F, .RHS = &[0]Symbol{} }
};

test "printProds" {
    print("AAAH\n", .{});
    for (grammar) |prod| {
        prod.debugPrint();
        print("\n", .{});
    }
}
