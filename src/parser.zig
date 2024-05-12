const std = @import("std");
const spec = @import("specification.zig");
const Token = spec.Token;
const TokenType = spec.TokenType;
const NonTerminalSymbol = spec.NonTerminalSymbol;
const Symbol = spec.Symbol;
const Production = spec.Production;
const grammar = spec.grammar;
const print = std.debug.print;
const TerminalSymbolSet = std.bit_set.StaticBitSet(numTerminalSymbols);

pub fn parse(input: []Token) bool {
    _ = input;
    return true;
}

const ParseTable = makeTabe: {
    break :makeTabe undefined;
};

// Generating state transition automata

const ParserState = struct {
    id: usize,
    items: []const Item,

    pub fn closure(self: *const @This(), outId: ?usize) @This() {
        var addedItem = true;
        var editable = self.items[0..].*;
        var out: []Item = &editable;
        while (addedItem) {
            addedItem = false;
            for (out) |item| {
                // There have to be symbols following the current position.
                if (item.dotPos >= item.prod.RHS.len) {
                    continue;
                }
                // The symbol following the current position must be nonterminal.
                switch (item.prod.RHS[item.dotPos]) {
                    .Terminal => continue,
                    .NonTerminal => |symbol| {
                        const followSymbs = item.prod.RHS[item.dotPos + 1 ..];
                        var followFirsts = calcFirst(followSymbs);
                        if (calcNullable(followSymbs)) {
                            followFirsts.setUnion(item.lookaheadSymbols);
                        }
                        for (&grammar) |*prod| {
                            if (prod.LHS != symbol) {
                                continue;
                            }
                            var newItem = Item{
                                .prod = prod,
                                .dotPos = 0,
                                .lookaheadSymbols = followFirsts,
                            };
                            for (out) |*existingItem| {
                                if (existingItem.eqlIgnoreLA(&newItem)) {
                                    const existingLAs = existingItem.lookaheadSymbols;
                                    if (existingLAs.supersetOf(followFirsts)) {
                                        // If our new one exactle matches one in the set we stop everything
                                        break;
                                    }
                                    // otherwise we add to the follow set.
                                    addedItem = true;
                                    // @compileLog(existingItem.lookaheadSymbols);
                                    existingItem.lookaheadSymbols.setUnion(newItem.lookaheadSymbols);
                                    // @compileLog(existingItem.lookaheadSymbols);
                                    break;
                                }
                            } else {
                                // Gets here if eqlIgnoreLA never hits
                                addedItem = true;
                                var newOut = (out ++ .{newItem}).*;
                                out = &newOut;
                            }
                        }
                    },
                }
            }
        }
        const realOut = out[0..].*;
        return .{
            .id = outId orelse 0,
            .items = &realOut,
        };
    }

    pub fn goto(self: *const @This(), transitionSymb: Symbol, outId: ?usize) @This() {
        var outInitial: []const Item = &.{};
        for (self.items) |item| {
            // If there is a next item and that item equals our transition symbol
            if (item.dotPos < item.prod.RHS.len and item.prod.RHS[item.dotPos].eql(transitionSymb)) {
                outInitial = outInitial ++ .{.{
                    .prod = item.prod,
                    .dotPos = item.dotPos + 1,
                    .lookaheadSymbols = item.lookaheadSymbols,
                }};
            }
        }
        const outStateInitial: @This() = .{
            .id = outId orelse 0,
            .items = outInitial,
        };
        return outStateInitial.closure(outId);
    }

    pub fn printSelf(self: *const @This()) void {
        print("Parser State: {}\n", .{self.id});
        for (self.items) |item| {
            item.printSelf();
        }
    }
};

const Item = struct {
    prod: *const Production, // Index into specification.grammar of the production this item represents.
    dotPos: usize, // Index of the symbol that the dot is immediately before.
    lookaheadSymbols: TerminalSymbolSet, // Set of all tokens that could follow this item. Indecies into TokenType.

    pub fn eqlStrict(self: *const @This(), other: *const @This()) bool {
        return self.prod == other.prod and
            self.dotPos == other.dotPos and
            self.lookaheadSymbols.eql(other.lookaheadSymbols);
    }

    pub fn eqlIgnoreLA(self: *const @This(), other: *const @This()) bool {
        return self.prod == other.prod and
            self.dotPos == other.dotPos;
    }

    pub fn printSelf(self: *const @This()) void {
        print("{s} ->", .{@tagName(self.prod.LHS)});
        for (self.prod.RHS, 0..) |symb, i| {
            if (i == self.dotPos) {
                print(" •", .{});
            }
            print(" {s}", .{switch (symb) {
                .NonTerminal => |nonTermSymb| @tagName(nonTermSymb),
                .Terminal => |termSymb| @tagName(termSymb),
            }});
        }
        if (self.dotPos == self.prod.RHS.len) {
            print(" •", .{});
        }
        print(" , {{", .{});
        var iter = self.lookaheadSymbols.iterator(.{});
        while (iter.next()) |ttInd| {
            const tt: TokenType = @enumFromInt(ttInd);
            print(" {s}", .{@tagName(tt)});
        }
        print(" }}\n", .{});
    }
};

const ParseActionType = enum {
    SHIFT,
    REDUCE,
    ACCEPT,
    ERROR,
};

const ParseAction = union(ParseActionType) {
    SHIFT: usize,
    REDUCE: usize,
    ACCEPT: void,
    ERROR: void,
};

// Properties of the grammar useful for parsing:
const numTerminalSymbols = @typeInfo(TokenType).Enum.fields.len;
const numNonterminalSymbols = @typeInfo(NonTerminalSymbol).Enum.fields.len;
const numSymbols = numTerminalSymbols + numNonterminalSymbols;

const nullable: [numSymbols]bool = calcNullables: {
    var out = [_]bool{false} ** numSymbols;
    var altered = false;
    for (spec.grammar) |prod| {
        if (prod.RHS.len == 0) {
            out[symbInd(.{ .NonTerminal = prod.LHS })] = true;
            altered = true;
        }
    }
    while (altered) {
        altered = false;
        ruleLoop: for (spec.grammar) |prod| {
            const lhsInd = symbInd(.{ .NonTerminal = prod.LHS });
            if (out[lhsInd]) {
                // Already known to be nullable. skip
                continue;
            }
            for (prod.RHS) |symb| {
                // If we encounter a non-nullable symbol
                if (!out[symbInd(symb)]) {
                    // We can continue onto the next grammar rule
                    continue :ruleLoop;
                }
            }
            // If we never continued in the above loop we get here:
            // We never encountered a non-nullable, so mark current as nullable.
            altered = true;
            out[lhsInd] = true;
        }
    }
    break :calcNullables out;
};

fn fetchNullable(symb: Symbol) bool {
    return nullable[symbInd(symb)];
}

fn calcNullable(sequence: []const Symbol) bool {
    for (sequence) |symb| {
        if (!fetchNullable(symb)) {
            return false;
        }
    }
    return true;
}

const first: [numSymbols]TerminalSymbolSet = calcFirsts: {
    var out: [numSymbols]TerminalSymbolSet = .{TerminalSymbolSet.initEmpty()} ** numSymbols;
    // Set the first set of all terminal symbols to be equal to that symbol.
    for (0..numTerminalSymbols) |i| {
        out[i].set(i);
    }
    var altered = true;
    while (altered) {
        altered = false;
        for (grammar) |prod| {
            const oldFirst = out[symbInd(.{ .NonTerminal = prod.LHS })];
            var newFirst = &out[symbInd(.{ .NonTerminal = prod.LHS })];
            // if (prod.RHS.len == 0){
            //     continue;
            // }
            for (prod.RHS) |symb| {
                newFirst.setUnion(out[symbInd(symb)]);
                if (!fetchNullable(symb)) {
                    break;
                }
            }
            if (!oldFirst.eql(newFirst.*)) {
                altered = true;
            }
        }
    }
    break :calcFirsts out;
};

fn fetchFirst(symb: Symbol) TerminalSymbolSet {
    return first[symbInd(symb)];
}

fn calcFirst(sequence: []const Symbol) TerminalSymbolSet {
    var out = TerminalSymbolSet.initEmpty();
    for (sequence) |symb| {
        out.setUnion(fetchFirst(symb));
        if (!fetchNullable(symb)) {
            break;
        }
    }
    return out;
}

const follow = calcFollows: {
    var out: [numSymbols]TerminalSymbolSet = .{TerminalSymbolSet.initEmpty()} ** numSymbols;
    var altered = true;
    while (altered) {
        altered = false;
        for (grammar) |prod| {
            for (prod.RHS, 0..) |symb, i| {
                switch (symb) {
                    .Terminal => continue,
                    .NonTerminal => |_| {
                        const oldFollow = out[symbInd(symb)];
                        var newFollow = &out[symbInd(symb)];
                        var followingNullable = true;
                        for (prod.RHS[i + 1 ..]) |followingSymb| {
                            newFollow.setUnion(fetchFirst(followingSymb));
                            if (!fetchNullable(followingSymb)) {
                                followingNullable = false;
                                break;
                            }
                        }
                        if (followingNullable) {
                            newFollow.setUnion(out[symbInd(.{ .NonTerminal = prod.LHS })]);
                        }
                        if (!oldFollow.eql(newFollow.*)) {
                            altered = true;
                        }
                    },
                }
            }
        }
    }
    break :calcFollows out;
};

fn fetchFollow(symb: Symbol) TerminalSymbolSet {
    return follow[symbInd(symb)];
}

// Gets index of symbol into nullable, first, & follow arrays.
fn symbInd(symb: Symbol) usize {
    return switch (symb) {
        .Terminal => |tt| @intFromEnum(tt),
        .NonTerminal => |nts| numTerminalSymbols + @intFromEnum(nts),
    };
}

test "nullableTest" {
    print("\n{any}\n", .{nullable});
    print("Calc: {}\n", .{calcNullable(&[_]Symbol{.{ .NonTerminal = .F }})});
}

fn printTSymbSet(set: *const TerminalSymbolSet) void {
    var iter = set.iterator(.{});
    if (iter.next()) |firstT| {
        const fe: TokenType = @enumFromInt(firstT);
        print(" {{{s}", .{@tagName(fe)});
        while (iter.next()) |ttind| {
            const e: TokenType = @enumFromInt(ttind);
            print(", {s}", .{@tagName(e)});
        }
        print("}}\n", .{});
    } else {
        print("{{}}\n", .{});
    }
}

test "first test" {
    for (first) |set| {
        printTSymbSet(&set);
    }
}

test "follow test" {
    for (follow) |set| {
        printTSymbSet(&set);
    }
}

test "state ops test" {
    @setEvalBranchQuota(3000);
    const baseState = comptime ParserState{ .id = 0, .items = &.{.{
        .prod = &grammar[0],
        .dotPos = 0,
        .lookaheadSymbols = TerminalSymbolSet.initEmpty(),
    }} };
    const closure = comptime baseState.closure(null);
    print("Base pos closure:\n", .{});
    for (closure.items) |item| {
        item.printSelf();
    }
    print("Transition on T:\n", .{});
    const c2 = comptime closure.goto(.{ .NonTerminal = .T }, null);
    for (c2.items) |item| {
        item.printSelf();
    }
}
