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
const SymbolSet = std.bit_set.StaticBitSet(numSymbols);

pub fn parse(input: []Token) bool {
    _ = input;
    return true;
}

const TableRow = [numSymbols]ParseAction;
const ParseTable = makeTabe: {
    @setEvalBranchQuota(1000000);
    const blankRow = [1]ParseAction{.{ .ERROR = {} }} ** numSymbols;
    var out: []TableRow = &.{};

    const baseRule = &grammar[0];
    if (!baseRule.RHS[baseRule.RHS.len - 1].eql(.{ .Terminal = .EOF })) {
        @compileError("Grammar error! First production must end in an EOF token.");
    }

    const initialItem = Item{
        .prod = baseRule,
        .dotPos = 0,
        .lookaheadSymbols = TerminalSymbolSet.initEmpty(),
    };

    // Initialize states seen with a state containing closure of base grammar rule
    var editable = [1]ParserState{ParserState.closure(&.{ .id = 0, .items = &.{initialItem} }, 0)};
    var states: []ParserState = &editable;
    var unprocessed: []const *ParserState = &.{&states[0]};

    while (unprocessed.len > 0) {
        // Pop unprocessed item from stack
        const currentParseState: *const ParserState = unprocessed[0];
        unprocessed = unprocessed[1..];

        var checkedSymbols = SymbolSet.initEmpty();
        var currentActions: TableRow = blankRow;

        for (currentParseState.items) |*item| {
            // If the dot is NOT at it's rightmost position
            if (item.dotPos < item.prod.RHS.len) {
                // Read the symbol immediately after the dot
                const symb = item.prod.RHS[item.dotPos];

                if (symb.eql(.{ .Terminal = .EOF })) {
                    addShift(&currentActions, symb, 0);
                    checkedSymbols.set(symbInd(symb));
                    continue;
                }

                // If that symbol has not already been checked for this state
                if (!checkedSymbols.isSet(symbInd(symb))) {
                    // It has now
                    checkedSymbols.set(symbInd(symb));
                    // Eat the symbol (shift dot left)
                    const newParseState = currentParseState.goto(symb, states.len);
                    // DestID is the state we will transition into. Could be new or existing.
                    var destID = newParseState.id;
                    // Now we check if the core of the state created by eating the symbol equals the core of any existing state
                    for (states) |*existingState| {
                        if (newParseState.eqlIgnoreLA(existingState)) {
                            // At this point we have found a state (existingState) whose core equals that of the created state (newParseState)
                            // Merge the two:
                            const mergedState = ParserState.merge(existingState, &newParseState);

                            if (mergedState.id == existingState.id) {
                                // MERGED IS DIFFERENT FROM EXISTING
                                // Their LAs are different so we set the existing to be the merged and mark it for reprocessing
                                destID = mergedState.id;
                                states[mergedState.id] = mergedState;
                                unprocessed = unprocessed ++ .{&states[mergedState.id]};
                            } else {
                                // MERGED IS THE SAME AS EXISTING. Discard it.
                                // Make transition into existing
                                destID = existingState.id;
                            }
                            break;
                        }
                    } else { // I <3 for-else.
                        // We did not break. Therefore no matches were found and newParseState is truly new.
                        // Add it to the list and mark for processing
                        var newStates = (states ++ .{newParseState}).*;
                        states = &newStates;
                        unprocessed = unprocessed ++ .{&states[newParseState.id]};
                    }
                    // Regardless of if the new state was merged, discarded, or was new, we need to add a transition to it
                    // Add transition:
                    addShift(&currentActions, symb, destID);
                }
            } else {
                // Dot at end. Time to reduce
                // Lookahead iter
                var LAiter = item.lookaheadSymbols.iterator(.{});
                while (LAiter.next()) |termID| {
                    switch (currentActions[termID]) {
                        .ERROR => {
                            // Good to reduce. No conflict.
                            currentActions[termID] = .{ .REDUCE = item.prod };
                        },
                        .REDUCE => |existingProd| {
                            if (existingProd == item.prod) {
                                // Somehow that reduce rule already exists.
                                // Probably shouldn't happen but idk so handling it just in case.
                                // By handling it I mean not handling it since we're all good.
                                // No conflict.
                            } else {
                                const errorToken: TokenType = @enumFromInt(termID);
                                @compileLog("Offending rule 1: ", item.prod.*);
                                @compileLog("Offending rule 2: ", existingProd.*);
                                @compileError("Reduce/Reduce conflict found when generating LALR parser on token: " ++ @tagName(errorToken));
                            }
                        },
                        .SHIFT, .ACCEPT => {
                            const errorToken: TokenType = @enumFromInt(termID);
                            @compileError("Shift/Reduce conflict found when generating LALR parser on token: " ++ @tagName(errorToken));
                        },
                    }
                }
            }
        }

        // We are done with the for loop. We have checked every item in the state. Now add the state's fully-formed actions to output:
        if (currentParseState.id >= out.len) {
            var newActions = (out ++ .{currentActions}).*;
            out = &newActions;
        } else {
            out[currentParseState.id] = currentActions;
        }
    }

    // @compileLog(states[9]);

    const outReal = out[0..].*;
    break :makeTabe outReal;
};

fn addShift(row: *TableRow, symb: Symbol, dest: usize) void {
    const transInd = symbInd(symb);
    switch (row.*[transInd]) {
        .ERROR => {
            // Good to shift. No conflict.
            if (symb.eql(.{ .Terminal = .EOF })) {
                row.*[transInd] = .{ .ACCEPT = {} };
            } else {
                row.*[transInd] = .{ .SHIFT = dest };
            }
        },
        .REDUCE => |_| {
            const errorToken: TokenType = @enumFromInt(transInd);
            @compileError("Shift/Reduce conflict found when generating LALR parser on token: " ++ @tagName(errorToken));
        },
        .SHIFT, .ACCEPT => unreachable,
    }
}

fn printParseTable(table: []const TableRow) void {
    print("    ", .{});
    for (0..numTerminalSymbols) |termI| {
        const tt: TokenType = @enumFromInt(termI);
        var tn = @tagName(tt);
        if (tn.len > 4) {
            print(" {s}", .{tn[0..4]});
        } else {
            print(" {s: <4}", .{tn});
        }
    }
    for (0..numNonterminalSymbols) |ntI| {
        const tt: NonTerminalSymbol = @enumFromInt(ntI);
        var tn = @tagName(tt);
        if (tn.len > 4) {
            print(" {s}", .{tn[0..4]});
        } else {
            print(" {s: <4}", .{tn});
        }
    }
    print("\n", .{});
    for (table, 0..) |row, i| {
        print("{d: >3}:", .{i});
        for (row) |action| {
            switch (action) {
                .SHIFT => |dest| {
                    print(" s{d: <3}", .{dest});
                },
                .ERROR => {
                    print(" e   ", .{});
                },
                .ACCEPT => {
                    print(" a   ", .{});
                },
                .REDUCE => |prod| {
                    const baseAddr: [*]const Production = @ptrCast(&grammar);
                    const prodAddr: [*]const Production = @ptrCast(prod);
                    const diff = (@intFromPtr(prodAddr) - @intFromPtr(baseAddr)) / @sizeOf(Production);
                    print(" r{d: <3}", .{diff});
                },
            }
        }
        print("\n", .{});
    }
}

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

    pub fn eql(self: *const @This(), other: *const @This()) bool {
        for (self.items, other.items) |*itm1, *itm2| {
            if (!itm1.eqlStrict(itm2)) {
                return false;
            }
        }
        return true;
    }

    pub fn eqlIgnoreLA(self: *const @This(), other: *const @This()) bool {
        if (self.items.len != other.items.len) {
            return false;
        }
        for (self.items, other.items) |*itm1, *itm2| {
            if (!itm1.eqlIgnoreLA(itm2)) {
                return false;
            }
        }
        return true;
    }

    /// Returns a new, merged object.
    /// Id = base.id + 100 if returned object is the same as base.
    /// Id = base.id if returned val is different from base.
    pub fn merge(base: *const @This(), new: *const @This()) @This() {
        var outItems: [base.items.len]Item = undefined;
        var isDiff = false;
        for (base.items, new.items, 0..) |*baseItm, *newItm, i| {
            var newSymbs = baseItm.lookaheadSymbols;
            newSymbs.setUnion(newItm.lookaheadSymbols);
            outItems[i] = .{
                .prod = baseItm.prod,
                .dotPos = baseItm.dotPos,
                .lookaheadSymbols = newSymbs,
            };
            // If union is not equal to original set
            if (!isDiff and !outItems[i].lookaheadSymbols.eql(baseItm.lookaheadSymbols)) {
                isDiff = true;
            }
        }
        return .{
            .id = if (isDiff) base.id else base.id + 100,
            .items = &outItems,
        };
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
    REDUCE: *const Production,
    ACCEPT: void,
    ERROR: void,

    pub fn isError(self: @This()) bool {
        return switch (self) {
            .ERROR => true,
            else => false,
        };
    }
};

// Properties of the grammar useful for parsing:

// Minus one since notoken.
const numTerminalSymbols = @typeInfo(TokenType).Enum.fields.len - 1;
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
    closure.printSelf();
    print("Transition on T:\n", .{});
    const c2 = comptime closure.goto(.{ .NonTerminal = .T }, null);
    c2.printSelf();
}

test "Parse Table Test" {
    print("\n\nPARSE TABLE:\n", .{});
    printParseTable(&ParseTable);
}
