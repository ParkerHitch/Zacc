const spec = @import("specification.zig");
const TokenType = spec.TokenType;
const std = @import("std");
const print = std.debug.print;
const BoundedArr256 = std.BoundedArray(AutomataNode, 256);

// Generates and stores NONDETERMINISTIC FA for the spec
pub const specNodalNFA: NodalFA = nodalNFAGen: {
    const tokenTypes = std.meta.fields(TokenType);
    var tonkenNodalNFAs: [tokenTypes.len]NodalFA = undefined;

    for (tokenTypes, 0..) |e, i| {
        const tt: TokenType = @enumFromInt(e.value);
        const regex = tt.getRegex();
        tonkenNodalNFAs[i] = genNodalNFA(regex, tt) catch {
            @compileLog("INVALIDREGEX FOR: ", tt);
            break :nodalNFAGen undefined;
        };
    }

    var mergedNFA: NodalFA = undefined;
    var mergedNodes: []const AutomataNode = &[0]AutomataNode{};
    var baseNode: AutomataNode = .{
        .id = 0,
    };

    mergedNFA.acceptingNodes = &[0]usize{};
    mergedNFA.acceptingTokens = &[0]TokenType{};
    var id = 1;
    for (tonkenNodalNFAs) |nfa| {
        const zeroId = id;
        baseNode.addExit(0, zeroId);
        for (nfa.nodes) |node| {
            var newNode: AutomataNode = .{
                .id = node.id + zeroId,
                .acceptsToken = node.acceptsToken,
            };
            std.debug.assert(newNode.id == id);
            if (newNode.acceptsToken != TokenType.NOTOKEN) {
                mergedNFA.acceptingNodes = (mergedNFA.acceptingNodes orelse unreachable) ++ .{id};
                mergedNFA.acceptingTokens = (mergedNFA.acceptingTokens orelse unreachable) ++ .{newNode.acceptsToken};
            }

            for (node.transitionKeys, node.transitionDests) |k, d| {
                newNode.transitionKeys = newNode.transitionKeys ++ .{k};
                newNode.transitionDests = newNode.transitionDests ++ .{d + zeroId};
            }
            mergedNodes = mergedNodes ++ .{newNode};
            id += 1;
        }
    }
    mergedNodes = .{baseNode} ++ mergedNodes;
    mergedNFA.baseNode = &mergedNFA.nodes[0];
    mergedNFA.nodes = mergedNodes;

    const out = mergedNFA.getRuntimeUsable();

    break :nodalNFAGen out;
};

fn genNodalNFA(regex: []const u8, acceptingType: TokenType) InvalidRegexError!NodalFA {
    var nodeList = BoundedArr256.init(0) catch unreachable;
    const NFA = try createForContext(regex, 0, 0, &nodeList);
    NFA.endNode.acceptsToken = acceptingType;

    const listConst = nodeList.constSlice()[0..].*;

    return .{
        .nodes = &listConst,
        .baseNode = &listConst[0],
    };
}

fn createForContext(regex: []const u8, baseID: usize, parenLvl: u8, arr: *BoundedArr256) InvalidRegexError!StartAndEnd {
    var currentID = baseID;
    const baseNode = try AutomataNode.addNewToArr(currentID, TokenType.NOTOKEN, arr);
    currentID += 1;
    var currentNode = try AutomataNode.addNewToArr(currentID, TokenType.NOTOKEN, arr);
    currentID += 1;
    baseNode.addExit(0, currentNode.id);
    var previousNode: *AutomataNode = baseNode;

    var escaped: bool = false;
    var i: usize = 0;
    var c: u8 = if (regex.len > 0) regex[0] else 0;
    while (i < regex.len) : (i += 1) {
        c = regex[i];
        if (!escaped) {
            if (c == '\\') {
                escaped = true;
                continue;
            } else if (c == '(') {
                const inner = try createForContext(regex[i + 1 ..], currentID, parenLvl + 1, arr);
                currentNode.addExit(0, inner.startNode.id);
                currentID = inner.endNode.id + 1;
                previousNode = currentNode;
                currentNode = inner.endNode;
                i += inner.charCount;
                if (i >= regex.len)
                    break;
                continue;
            } else if (parenLvl > 0 and c == ')') {
                i += 1;
                break;
            } else if (c == '|') {
                const rhs = try createForContext(regex[i + 1 ..], currentID, parenLvl, arr);
                baseNode.addExit(0, rhs.startNode.id);
                currentID = rhs.endNode.id + 1;
                i += rhs.charCount + 1;
                const mergedEnd = try AutomataNode.addNewToArr(currentID, TokenType.NOTOKEN, arr);
                currentID += 1;
                currentNode.addExit(0, mergedEnd.id);
                rhs.endNode.addExit(0, mergedEnd.id);
                currentNode = mergedEnd;
                break;
            } else if (c == '*') {
                const newBlank = try AutomataNode.addNewToArr(currentID, TokenType.NOTOKEN, arr);
                currentID += 1;
                previousNode.addExit(0, currentNode.id);
                currentNode.addExit(0, previousNode.id);
                currentNode.addExit(0, newBlank.id);
                currentNode = newBlank;
                continue;
            } else if (c == '?') {
                previousNode.addExit(0, currentNode.id);
                continue;
            } else if (c == '+') {
                currentNode.addExit(0, previousNode.id);
                continue;
            } else if (c == '[') {
                const newNode = try AutomataNode.addNewToArr(currentID, TokenType.NOTOKEN, arr);
                currentID += 1;
                const charJump = try currentNode.addMacroExits(regex[i + 1 ..], newNode.id);
                previousNode = currentNode;
                currentNode = newNode;
                i += charJump;
                continue;
            }
        }
        const newNode = try AutomataNode.addNewToArr(currentID, TokenType.NOTOKEN, arr);
        currentID += 1;
        currentNode.addExit(c, newNode.id);
        previousNode = currentNode;
        currentNode = newNode;
    }

    return .{
        .startNode = baseNode,
        .endNode = currentNode,
        .charCount = i,
    };
}

// ======= TYPES =======

const InvalidRegexError = error{
    InvalidRegex,
    RegexTooComplex,
    InvalidMacro,
};

const StartAndEnd = struct {
    startNode: *AutomataNode,
    endNode: *AutomataNode,
    charCount: usize, // Number of chars used. First char + this = null char or closing paren.
};

pub const AutomataNode = struct {
    id: usize,
    acceptsToken: TokenType = .NOTOKEN,
    transitionKeys: []const u8 = &[0]u8{},
    transitionDests: []const usize = &[0]usize{},

    pub fn addNewToArr(id: usize, acceptToken: TokenType, arr: *BoundedArr256) !*@This() {
        arr.append(@This(){
            .id = id,
            .acceptsToken = acceptToken,
        }) catch return InvalidRegexError.RegexTooComplex;
        return &arr.slice()[arr.len - 1];
    }

    pub fn addExit(self: *@This(), key: u8, dest: usize) void {
        self.transitionKeys = self.transitionKeys ++ .{key};
        self.transitionDests = self.transitionDests ++ .{dest};
    }

    pub fn addMacroExits(self: *@This(), macroStart: []const u8, dest: usize) !usize {
        var i: usize = 0;
        while (macroStart[i] != ']') : (i += 3) {
            if (macroStart[i + 1] != '-' or macroStart[i + 2] <= macroStart[i]) {
                return InvalidRegexError.InvalidMacro;
            }
            for (macroStart[i]..macroStart[i + 2] + 1) |c| {
                self.addExit(c, dest);
            }
        }
        return i + 1;

        // int i=0;
        // int charCnt = 0;
        // do{
        //     if(macroStart[i+1]!='-' || macroStart[i+2]<=macroStart[i]){
        //         printf("Invalid range macro.\n");
        //         return -1;
        //     }
        //     charCnt += macroStart[i+2] - macroStart[i] + 1;
        //     i+=3;
        // } while(macroStart[i]!=']');
        // int newExitCnt = startNode->exitCount+charCnt;
        // startNode->exitChars = realloc(startNode->exitChars, newExitCnt*sizeof(char));
        // startNode->exitNodes = realloc(startNode->exitNodes, newExitCnt*sizeof(Node*));
        // int ptr = startNode->exitCount;
        // startNode->exitCount=newExitCnt;
        // i=0;
        // do{
        //     for(int j=macroStart[i]; j<=macroStart[i+2]; j++){
        //         startNode->exitChars[ptr] = j;
        //         startNode->exitNodes[ptr] = endNode;
        //         ptr++;
        //     }
        //     i+=3;
        // } while(macroStart[i]!=']');
        // return i;
        //
    }
};

pub const NodalFA = struct {
    nodes: []const AutomataNode,
    baseNode: *const AutomataNode,
    acceptingNodes: ?[]const usize = null,
    acceptingTokens: ?[]const TokenType = null,

    pub fn printSelf(self: @This()) void {
        for (self.nodes) |node| {
            print("{}", .{node.id});
            if (node.acceptsToken != .NOTOKEN) {
                print(" - ACCEPTS: {}\n", .{node.acceptsToken});
            } else {
                print("\n", .{});
            }
            for (node.transitionKeys, node.transitionDests) |k, d| {
                if (k != 0) {
                    print("|-\"{c}\"->{d}\n", .{ k, d });
                } else {
                    print("|----->{d}\n", .{d});
                }
            }
        }
    }

    pub inline fn getRuntimeUsable(comptime self: *const @This()) NodalFA {
        const outNodes = getNodes: {
            var tempNodes: [self.nodes.len]AutomataNode = undefined;

            for (self.nodes, 0..) |node, i| {
                const keysConst: [node.transitionKeys.len]u8 = (node.transitionKeys[0..]).*;
                const destsConst: [node.transitionDests.len]usize = (node.transitionDests[0..]).*;
                // for (node.transitionDests, 0..) |dest, j| {
                //     destsTemp[j] = &tempNodes[dest.id];
                // }
                // const destsConst = destsTemp;
                tempNodes[i] = .{
                    .id = node.id,
                    .acceptsToken = node.acceptsToken,
                    .transitionKeys = &keysConst,
                    .transitionDests = &destsConst,
                };
            }
            break :getNodes tempNodes;
        };

        const out: NodalFA = .{
            .nodes = &outNodes,
            .baseNode = &outNodes[0],
            .acceptingNodes = self.acceptingNodes,
            .acceptingTokens = self.acceptingTokens,
        };
        return out;
    }
};

test "NonExaustiveIter" {
    inline for (std.meta.fields(TokenType)) |tt| {
        const val: TokenType = @enumFromInt(tt.value);
        print("{s}\n", .{val.getRegex()});
    }
}

test "Node Func Tests" {
    // comptime var testArr: BoundedArr256 = BoundedArr256.init(0) catch unreachable;
    // comptime var testNode1 = try AutomataNode.addNewToArr(0, TokenType.NOTOKEN, &testArr);
    // const testNode2 = try AutomataNode.addNewToArr(1, TokenType.NOTOKEN, &testArr);
    //
    // testNode1.addExit('a', testNode2);
    //
    // print("{any}", testNode1.transitionKeys);
}

fn runTest(comptime regex: []const u8, comptime acceptType: ?TokenType) !void {
    print("Testing Regex: \"{s}\"! \n\n", .{regex});
    const possibleNFA = comptime genNodalNFA(regex, acceptType orelse TokenType.ID);
    const testNFA: ?NodalFA = comptime if (possibleNFA) |fa| fa.getRuntimeUsable() else |_| null;
    // comptime (try genNodalNFA(regex, acceptType orelse TokenType.ID)).getRuntimeUsable();
    if (testNFA) |nfa| {
        nfa.printSelf();
    } else {
        print("ERROR!!! {any}\n", .{possibleNFA});
        // return possibleNFA;
    }
    print("\nDone!\n", .{});
}

test "Runtime Test" {
    try runTest("a|b|c", null);
    try runTest("abc*", null);
    try runTest("a(b)c", null);
    try runTest("a(b|2)c", null);
    try runTest("a(1|2|3)*", null);
    try runTest("a[0-9]", null);
    try runTest("1[a-zA-Z]", null);
    try runTest("a([1-3]|d)*f", null);
    try runTest("(a|b|c)(1|2|3)", null);
    try runTest("(a|b|c)123", null);
}

test "While" {
    var i: u32 = 0;
    while (i < 10) : (i += 1) {}
    print("\n{}\n", .{i});
}

test "Lang Test Individual" {
    const tokenTypeFields = comptime std.meta.fields(TokenType);
    const tokenTypes = comptime getTTs: {
        var arr: [tokenTypeFields.len]TokenType = undefined;
        for (tokenTypeFields, 0..) |tt, i| {
            arr[i] = @enumFromInt(tt.value);
        }
        const out = arr;
        break :getTTs out;
    };
    const regexes = comptime getRegs: {
        var arr: [tokenTypes.len][]const u8 = undefined;
        for (tokenTypes, 0..) |tt, i| {
            arr[i] = tt.getRegex();
        }
        const out = arr;
        break :getRegs out;
    };

    inline for (regexes) |r| {
        try runTest(r, null);
    }
}

test "Spec Test NFA Combined" {
    print("\nTESTING SPEC COMBINED\n", .{});
    specNodalNFA.printSelf();
}
