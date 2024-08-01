const std = @import("std");
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const lexer = @import("lexer.zig");
const print = std.debug.print;

const config = @import("config");
const verboseParsing = config.verboseParsing;

pub fn Parser(comptime Specification: type) type {
    const TokenKind = Specification.TokenKind;
    const NonTerminalSymbolKind = Specification.NonTerminalSymbolKind;
    const Token = Specification.Token;
    const Symbol = Specification.Symbol;
    const SymbolData = Specification.SymbolData;
    const SemanticDataType = Specification.SemanticDataType;
    const Production = Specification.Production;
    const grammar: []const Production = Specification.grammar;

    // Minus one since notoken.
    const numTerminalSymbols = @typeInfo(TokenKind).Enum.fields.len - 1;
    const numNonterminalSymbols = @typeInfo(NonTerminalSymbolKind).Enum.fields.len;
    const numSymbols = numTerminalSymbols + numNonterminalSymbols;

    const TerminalSymbolSet = std.bit_set.StaticBitSet(numTerminalSymbols);
    const SymbolSet = std.bit_set.StaticBitSet(numSymbols);

    const ParseStackItem = struct {
        parseState: usize,
        symb: Symbol = undefined,
        data: SymbolData = undefined,
    };
    const ParseStack = std.ArrayListAligned(ParseStackItem, null);

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
            return self == .ERROR;
        }
    };

    const TableRow = [numSymbols]ParseAction;

    return struct {
        pub const ParseError = error{ UNEXPECTED_TOKEN, INCOMPLETE_INPUT };

        pub fn parseStream(input: []Token, allocator: Allocator) !SemanticDataType {
            var stack = try ParseStack.initCapacity(allocator, 20);
            defer stack.deinit();

            try stack.append(.{ .parseState = 0 });

            var currentParseState: usize = 0;
            var inputInd: usize = 0;

            while (inputInd < input.len) {
                const lookaheadToken = input[inputInd];
                // TODO: lookaheadToken.kind
                const lookaheadKind: TokenKind = lookaheadToken.kind;
                const currentAction = ParseTable[currentParseState][@intFromEnum(lookaheadKind)];
                // print("Stack: {any}\n", .{stack.items});
                switch (currentAction) {
                    .ERROR => {
                        print("Unexpected token: {s} (token # {d})\n", .{ @tagName(lookaheadKind), inputInd });
                        return ParseError.UNEXPECTED_TOKEN;
                    },
                    .ACCEPT => {
                        if (comptime verboseParsing)
                            print("Accepting from state {}\n", .{currentParseState});
                        try stack.append(.{ .parseState = 0, .symb = .{ .terminal = lookaheadKind }, .data = .{ .token = .{ .kind = .EOF, .src = "" } } });

                        const inputSymbData: []SymbolData = try allocator.alloc(SymbolData, stack.items.len - 1);
                        defer allocator.free(inputSymbData);

                        // Have to ignore first item. That is the base state. See stack.append before loop
                        for (stack.items[1..], 0..) |psi, i| {
                            inputSymbData[i] = psi.data;
                        }
                        const outData: SemanticDataType = grammar[0].semanticAction(inputSymbData);

                        return outData;
                    },
                    .SHIFT => |destState| {
                        if (comptime verboseParsing)
                            print("Shifting from {} into {} on token {s}\n", .{ currentParseState, destState, @tagName(lookaheadKind) });

                        currentParseState = destState;
                        try stack.append(.{ .parseState = destState, .symb = .{ .terminal = lookaheadKind }, .data = .{ .token = lookaheadToken } });
                        inputInd += 1;
                    },
                    .REDUCE => |prod| {
                        // + 1 since base state of 0.
                        // Idk if it is even possible to reach this condition
                        // if (prod.RHS.len > stack.items.len + 1) {
                        //     print("Unexpected token: {s} (token # {d})\n", .{@tagName(lookaheadToken), inputInd});
                        // }

                        if (comptime verboseParsing) {
                            print("Reducing on token {s} using rule: [", .{@tagName(lookaheadKind)});
                            prod.debugPrint();
                            print("]", .{});
                        }

                        const baseState = stack.items[stack.items.len - prod.RHS.len - 1].parseState;
                        const transitionInd = symbInd(.{ .nonTerminal = prod.LHS });

                        const newState = switch (ParseTable[baseState][transitionInd]) {
                            .SHIFT => |dest| dest,
                            else => unreachable,
                        };

                        if (comptime verboseParsing)
                            print(" (Into state: {})\n", .{newState});

                        currentParseState = newState;

                        const symbNum = prod.RHS.len;
                        const inputSymbData: []SymbolData = try allocator.alloc(SymbolData, symbNum);
                        defer allocator.free(inputSymbData);

                        for (stack.items[stack.items.len - symbNum ..], 0..) |psi, i| {
                            inputSymbData[i] = psi.data;
                        }

                        const outData: SemanticDataType = prod.semanticAction(inputSymbData);

                        try stack.replaceRange(stack.items.len - prod.RHS.len, prod.RHS.len, &.{.{ .parseState = newState, .symb = .{ .nonTerminal = prod.LHS }, .data = .{ .semanticData = outData } }});
                    },
                }
            }

            print("Incomplete input. Missing EOF.\n", .{});
            return ParseError.INCOMPLETE_INPUT;
        }

        const ParseTable = makeLalrTable: {
            @setEvalBranchQuota(100000000);
            const blankRow = [1]ParseAction{.{ .ERROR = {} }} ** numSymbols;
            var out: []TableRow = &.{};

            const baseRule = &(grammar[0]);

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

                        if (symb.eql(.{ .terminal = .EOF })) {
                            addShift(&currentActions, symb, 0);
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
                                        const errorToken: TokenKind = @enumFromInt(termID);
                                        @compileLog("Offending rule 1: ", item.prod.*);
                                        @compileLog("Offending rule 2: ", existingProd.*);
                                        @compileError("Reduce/Reduce conflict found when generating LALR parser on token: " ++ @tagName(errorToken));
                                    }
                                },
                                .SHIFT, .ACCEPT => {
                                    const errorToken: TokenKind = @enumFromInt(termID);
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
            break :makeLalrTable outReal;
        };

        fn addShift(row: *TableRow, symb: Symbol, dest: usize) void {
            const transInd = symbInd(symb);
            switch (row.*[transInd]) {
                .ERROR => {
                    // Good to shift. No conflict.
                    if (symb.eql(.{ .terminal = .EOF })) {
                        row.*[transInd] = .{ .ACCEPT = {} };
                    } else {
                        row.*[transInd] = .{ .SHIFT = dest };
                    }
                },
                .REDUCE => |prodPtr| {
                    const errorToken: TokenKind = @enumFromInt(transInd);
                    @compileError(std.fmt.comptimePrint("Shift/Reduce conflict found on token: {s}. Reduction uses rule: {s}", .{ @tagName(errorToken), prodPtr.makeComptimeStr() }));
                    // @compileError("Shift/Reduce conflict found when generating LALR parser on token: " ++ @tagName(errorToken));
                },
                .SHIFT, .ACCEPT => unreachable,
            }
        }

        fn printParseTable(table: []const TableRow) void {
            print("    ", .{});
            for (0..numTerminalSymbols) |termI| {
                const tt: TokenKind = @enumFromInt(termI);
                var tn = @tagName(tt);
                if (tn.len > 4) {
                    print(" {s}", .{tn[0..4]});
                } else {
                    print(" {s: <4}", .{tn});
                }
            }
            for (0..numNonterminalSymbols) |ntI| {
                const tt: NonTerminalSymbolKind = @enumFromInt(ntI);
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
                            .terminal => continue,
                            .nonTerminal => |symbol| {
                                const followSymbs = item.prod.RHS[item.dotPos + 1 ..];
                                var followFirsts = calcFirst(followSymbs);
                                if (calcNullable(followSymbs)) {
                                    followFirsts.setUnion(item.lookaheadSymbols);
                                }
                                for (grammar) |*prod| {
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
            lookaheadSymbols: TerminalSymbolSet, // Set of all tokens that could follow this item. Indecies into TokenKind.

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
                        .nonTerminal => |nonTermSymb| @tagName(nonTermSymb),
                        .terminal => |termSymb| @tagName(termSymb),
                    }});
                }
                if (self.dotPos == self.prod.RHS.len) {
                    print(" •", .{});
                }
                print(" , {{", .{});
                var iter = self.lookaheadSymbols.iterator(.{});
                while (iter.next()) |ttInd| {
                    const tt: TokenKind = @enumFromInt(ttInd);
                    print(" {s}", .{@tagName(tt)});
                }
                print(" }}\n", .{});
            }
        };

        // Properties of the grammar useful for parsing:

        const nullable: [numSymbols]bool = calcNullables: {
            var out = [_]bool{false} ** numSymbols;
            var altered = false;
            for (grammar) |prod| {
                if (prod.RHS.len == 0) {
                    out[symbInd(.{ .nonTerminal = prod.LHS })] = true;
                    altered = true;
                }
            }
            while (altered) {
                altered = false;
                ruleLoop: for (grammar) |prod| {
                    const lhsInd = symbInd(.{ .nonTerminal = prod.LHS });
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
            @setEvalBranchQuota(1000000);
            var out: [numSymbols]TerminalSymbolSet = .{TerminalSymbolSet.initEmpty()} ** numSymbols;
            // Set the first set of all terminal symbols to be equal to that symbol.
            for (0..numTerminalSymbols) |i| {
                out[i].set(i);
            }
            var altered = true;
            while (altered) {
                altered = false;
                for (grammar) |prod| {
                    const oldFirst = out[symbInd(.{ .nonTerminal = prod.LHS })];
                    var newFirst = &out[symbInd(.{ .nonTerminal = prod.LHS })];
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
                            .terminal => continue,
                            .nonTerminal => |_| {
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
                                    newFollow.setUnion(out[symbInd(.{ .nonTerminal = prod.LHS })]);
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
                .terminal => |tt| @intFromEnum(tt),
                .nonTerminal => |nts| numTerminalSymbols + @intFromEnum(nts),
            };
        }
    };
}

// test "nullableTest" {
//     print("\n{any}\n", .{nullable});
//     print("Calc: {}\n", .{calcNullable(&[_]Symbol{.{ .NonTerminal = .F }})});
// }
//
// fn printTSymbSet(set: *const TerminalSymbolSet) void {
//     var iter = set.iterator(.{});
//     if (iter.next()) |firstT| {
//         const fe: TokenKind = @enumFromInt(firstT);
//         print(" {{{s}", .{@tagName(fe)});
//         while (iter.next()) |ttind| {
//             const e: TokenKind = @enumFromInt(ttind);
//             print(", {s}", .{@tagName(e)});
//         }
//         print("}}\n", .{});
//     } else {
//         print("{{}}\n", .{});
//     }
// }
//
// test "first test" {
//     for (first) |set| {
//         printTSymbSet(&set);
//     }
// }
//
// test "follow test" {
//     for (follow) |set| {
//         printTSymbSet(&set);
//     }
// }
//
// test "state ops test" {
//     @setEvalBranchQuota(3000);
//     const baseState = comptime ParserState{ .id = 0, .items = &.{.{
//         .prod = &grammar[0],
//         .dotPos = 0,
//         .lookaheadSymbols = TerminalSymbolSet.initEmpty(),
//     }} };
//     const closure = comptime baseState.closure(null);
//     print("Base pos closure:\n", .{});
//     closure.printSelf();
//     print("Transition on T:\n", .{});
//     const c2 = comptime closure.goto(.{ .NonTerminal = .T }, null);
//     c2.printSelf();
// }
//
// test "Parse Table Test" {
//     print("\n\nPARSE TABLE:\n", .{});
//     printParseTable(&ParseTable);
// }
//
// test "Parsing Test" {
//     var allocator = std.testing.allocator;
//
//     const inFile: File = try std.fs.cwd().openFile("test.txt", .{ .mode = .read_only });
//     defer inFile.close();
//
//     var reader = try lexer.WholeFileBufferReader.init(inFile, allocator);
//     defer reader.deinit();
//
//     const lexed = try lexer.lexFile(&reader, allocator);
//
//     print("Does test.txt parse?\n", .{});
//     const parse = try parseStream(lexed, allocator);
//     if (parse) {
//         print("YES!!!!\n", .{});
//     } else {
//         print("NO :(\n", .{});
//     }
//
//     allocator.free(lexed);
// }
