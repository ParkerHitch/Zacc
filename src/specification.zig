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

    pub fn lexFromString(self: TokenType, sourceStr: []const u8) Token {
        return switch (self) {
            .ID => Token{ .ID = sourceStr },
            // Unreachable because regex picks good numbers for us
            .NUM => Token{ .NUM = std.fmt.parseFloat(f32, sourceStr) catch unreachable },
            .L_ASSIGN => Token{ .L_ASSIGN = {} },
            .R_ASSIGN => Token{ .R_ASSIGN = {} },
            .PLUS => Token{ .PLUS = {} },
            .MINUS => Token{ .MINUS = {} },
            .MULT => Token{ .MULT = {} },
            .DIV => Token{ .DIV = {} },
            .L_PAREN => Token{ .L_PAREN = {} },
            .R_PAREN => Token{ .R_PAREN = {} },
            .SEMICOLON => Token{ .SEMICOLON = {} },
            .NOTOKEN => Token{ .NOTOKEN = {} },
            .EOF => Token{ .EOF = {} },
        };
    }
};

pub const Token = union(TokenType) { EOF: void, ID: []const u8, L_ASSIGN: void, R_ASSIGN: void, NUM: f32, PLUS: void, MINUS: void, MULT: void, DIV: void, L_PAREN: void, R_PAREN: void, SEMICOLON: void, NOTOKEN: void };

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
    Terminal: Token,
    NonTerminal: NonTerminalSymbol,

    pub fn toShallow(self: @This()) ShallowSymbol {
        return self;
    }

    pub fn debugPrint(self: @This()) void {
        switch (self) {
            .Terminal => |tok| {
                print("{s}", .{@tagName(tok)});
                switch (tok) {
                    .ID => |id| print(": {s}", .{id}),
                    .NUM => |num| print(": {}", .{num}),
                    else => return,
                }
            },
            .NonTerminal => |nt| {
                print("{s}", .{@tagName(nt)});
            },
        }
    }
};

pub const ShallowSymbol = union(SymbolClass) {
    Terminal: TokenType,
    NonTerminal: NonTerminalSymbol,

    pub fn fromNormal(other: Symbol) @This() {
        return switch (other) {
            // Coerce Token to TokenType
            .Terminal => |tok| .{ .Terminal = tok },
            .NonTerminal => |nt| .{ .NonTerminal = nt },
        };
    }

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

fn doNothing(symbs: []const Symbol) void {
    for (symbs) |symb| {
        symb.debugPrint();
        print(", ", .{});
    }
    print("\n", .{});
}

pub const Production = struct {
    LHS: NonTerminalSymbol,
    RHS: []const ShallowSymbol,
    ParseAction: *const fn ([]const Symbol) void = doNothing,

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
        .RHS = &[_]ShallowSymbol{ .{ .NonTerminal = .SPRIME }, .{ .Terminal = .EOF } },
    },
    Production{
        .LHS = .SPRIME,
        .RHS = &[_]ShallowSymbol{ .{ .NonTerminal = .S }, .{ .Terminal = .SEMICOLON } },
    },
    Production{
        .LHS = .SPRIME,
        .RHS = &[_]ShallowSymbol{ .{ .NonTerminal = .SPRIME }, .{ .NonTerminal = .S }, .{ .Terminal = .SEMICOLON } },
    },
    Production{ .LHS = .S, .RHS = &[_]ShallowSymbol{
        .{ .Terminal = .ID },
        .{ .Terminal = .L_ASSIGN },
        .{ .NonTerminal = .E },
    } },
    Production{ .LHS = .S, .RHS = &[_]ShallowSymbol{
        .{ .NonTerminal = .E },
        .{ .Terminal = .R_ASSIGN },
        .{ .Terminal = .ID },
    } },
    Production{ .LHS = .E, .RHS = &[_]ShallowSymbol{
        .{ .NonTerminal = .E },
        .{ .Terminal = .PLUS },
        .{ .NonTerminal = .T },
    } },
    Production{ .LHS = .E, .RHS = &[_]ShallowSymbol{
        .{ .NonTerminal = .T },
    } },
    Production{ .LHS = .T, .RHS = &[_]ShallowSymbol{
        .{ .NonTerminal = .T },
        .{ .Terminal = .MULT },
        .{ .NonTerminal = .F },
    } },
    Production{ .LHS = .T, .RHS = &[_]ShallowSymbol{
        .{ .NonTerminal = .T },
        .{ .Terminal = .DIV },
        .{ .NonTerminal = .F },
    } },
    Production{ .LHS = .T, .RHS = &[_]ShallowSymbol{
        .{ .NonTerminal = .F },
    } },
    Production{ .LHS = .F, .RHS = &[_]ShallowSymbol{
        .{ .Terminal = .ID },
    } },
    Production{ .LHS = .F, .RHS = &[_]ShallowSymbol{
        .{ .Terminal = .NUM },
    } },
    Production{ .LHS = .F, .RHS = &[_]ShallowSymbol{
        .{ .Terminal = .L_PAREN },
        .{ .NonTerminal = .E },
        .{ .Terminal = .R_PAREN },
    } },
    // Production{ .LHS = .F, .RHS = &[0]ShallowSymbol{} }
};

test "printProds" {
    print("AAAH\n", .{});
    for (grammar) |prod| {
        prod.debugPrint();
        print("\n", .{});
    }
}
