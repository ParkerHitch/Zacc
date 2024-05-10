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

fn calcFirst(sequence: []Symbol) TerminalSymbolSet {
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
