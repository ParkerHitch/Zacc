const std = @import("std");
const print = std.debug.print;
const EnumField = std.builtin.Type.EnumField;

pub fn Token(comptime TokenKind_: type) type {
    @setEvalBranchQuota(100000);
    validateTokenKind(TokenKind_);

    return struct {
        const Token_ = @This();

        pub const TokenKind = TokenKind_;

        kind: TokenKind,
        src: []const u8,

        pub fn Production(comptime SemanticDataType: type) type {
            return struct {
                const Production_ = @This();

                pub const SymbolData = union(enum) { token: Token_, semanticData: SemanticDataType };

                rule: [:0]const u8,
                semanticAction: *const fn ([]SymbolData) SemanticDataType,

                pub fn CreateSpecification(comptime grammar: []const Production_, comptime options: CompilationOptions) type {
                    return Specification(Token_, SemanticDataType, SymbolData, Production_, grammar, options);
                }
            };
        }
    };
}

pub const CompilationOptions = struct {
    /// Enables the verbose lexing debugging feature.
    /// Prints each character and matched tokens to stderr.
    verboseLexing: bool = false,
    /// Enables the verbose parsing debugging feature.
    /// Prints each input token and all shift/reduce actions taken.
    verboseParsing: bool = false,
    /// A string that denotes the start of a line comment.
    lineCommentStart: ?[:0]const u8 = null,
    /// A string that denotes the start of a block comment.
    blockCommentStart: ?[:0]const u8 = null,
    /// A string that denotes the end of a block comment.
    blockCommentEnd: ?[:0]const u8 = null,
    /// Can block comments be nested?
    supportNestedBlockComments: bool = false,
    /// Characters that the compiler ignores.
    /// These characters cannot be used in tokens or comment delimiters.
    /// Code surrounded by these characters must be a sequence of valid tokens.
    whitespaceCharacters: []const u8 = &.{ ' ', '\n', '\t', '\r' },
};

// Return the specification type to be used in generating the compiler.
fn Specification(
    comptime Token_: type,
    comptime SemanticDataType_: type,
    comptime SymbolData_: type,
    comptime InputProduction: type,
    comptime inGrammar: []const InputProduction,
    comptime inOptions: CompilationOptions,
) type {
    @setEvalBranchQuota(100000);

    const NonTerminalSymbolKind_: type = CreateNonTerminalSymbolEnum(InputProduction, inGrammar);
    return struct {
        const Specification = @This();

        pub const options: CompilationOptions = inOptions;

        pub const TokenKind = std.meta.FieldType(Token_, .kind);
        pub const Token = Token_;

        pub const NonTerminalSymbolKind = NonTerminalSymbolKind_;

        pub const Symbol = union(enum) {
            terminal: TokenKind,
            nonTerminal: NonTerminalSymbolKind,

            pub fn fromStr(str: []const u8) ?@This() {
                const optNonTerminal = std.meta.stringToEnum(NonTerminalSymbolKind, str);
                const optTerminal = std.meta.stringToEnum(TokenKind, str);
                if (optNonTerminal) |nt| {
                    return .{ .nonTerminal = nt };
                } else if (optTerminal) |t| {
                    return .{ .terminal = t };
                } else {
                    return null;
                }
            }

            pub fn eql(self: @This(), other: @This()) bool {
                return switch (self) {
                    .terminal => |tt| switch (other) {
                        .terminal => |tt2| tt == tt2,
                        .nonTerminal => false,
                    },
                    .nonTerminal => |nts| switch (other) {
                        .terminal => false,
                        .nonTerminal => |nts2| nts == nts2,
                    },
                };
            }

            pub fn debugPrint(self: @This()) void {
                switch (self) {
                    .terminal => |val| print("{s}", .{@tagName(val)}),
                    .nonTerminal => |val| print("{s}", .{@tagName(val)}),
                }
            }
        };

        pub const SymbolData = SymbolData_;
        pub const SemanticDataType = SemanticDataType_;

        pub const Production = struct {
            const cprint = std.fmt.comptimePrint;

            LHS: NonTerminalSymbolKind,
            RHS: []const Symbol,
            semanticAction: *const fn ([]SymbolData) SemanticDataType,

            pub fn debugPrint(self: @This()) void {
                print("{s} ->", .{@tagName(self.LHS)});
                for (self.RHS) |symb| {
                    print(" {s}", .{switch (symb) {
                        .nonTerminal => |nonTermSymb| @tagName(nonTermSymb),
                        .terminal => |termSymb| @tagName(termSymb),
                    }});
                }
            }

            pub fn makeComptimeStr(self: @This()) []const u8 {
                var out: []const u8 = cprint("{s} ->", .{@tagName(self.LHS)});
                for (self.RHS) |symb| {
                    out = out ++ cprint(" {s}", .{switch (symb) {
                        .nonTerminal => |nonTermSymb| @tagName(nonTermSymb),
                        .terminal => |termSymb| @tagName(termSymb),
                    }});
                }
                return out;
            }

            pub fn eql(self: @This(), other: @This()) bool {
                return self.LHS == other.LHS and
                    std.mem.eql(Symbol, self.RHS, other.RHS) and
                    self.semanticAction == other.semanticAction;
            }
        };

        pub const grammar: []const Production = createGrammar(Production, InputProduction, inGrammar);
    };
}

/// Creates the grammar in the proper type out of strings
fn createGrammar(comptime Production: type, comptime InputProduction: type, comptime inputGrammar: []const InputProduction) []const Production {
    @setEvalBranchQuota(10000000);
    var productions: []const Production = &.{};
    const Symbol: type = @typeInfo(std.meta.FieldType(Production, .RHS)).Pointer.child;
    // const TokenKind: type = std.meta.FieldType(Symbol, .terminal);
    const NonTerminalSymbolKind: type = std.meta.FieldType(Symbol, .nonTerminal);

    for (inputGrammar) |inProd| {
        const rule = inProd.rule;

        var newProd = Production{ .LHS = undefined, .RHS = &.{}, .semanticAction = inProd.semanticAction };

        var arrowStart: usize = 0;

        for (rule[0 .. rule.len - 1], rule[1..], 0..) |char1, char2, i| {
            if (char1 == '-' and char2 == '>') {
                arrowStart = i;
                break;
            }
        }

        var charInd: i32 = arrowStart - 1;
        var symbolStart: usize = 0;
        var symbolEnd: usize = 0;

        while (rule[charInd] == ' ') : (charInd -= 1) {}
        symbolEnd = charInd + 1;
        while (charInd >= 0 and rule[charInd] != ' ') : (charInd -= 1) {}
        symbolStart = charInd + 1;

        const LHS: NonTerminalSymbolKind = std.meta.stringToEnum(NonTerminalSymbolKind, rule[symbolStart..symbolEnd]) orelse unreachable;
        newProd.LHS = LHS;

        var inSymb: bool = false;
        charInd = arrowStart + 2;
        while (charInd < rule.len) : (charInd += 1) {
            const char = rule[charInd];
            if (char == ' ') {
                if (inSymb) {
                    // Space in symbol: end of symbol
                    const symbStr = rule[symbolStart..charInd];
                    const optSymb = Symbol.fromStr(symbStr);
                    if (optSymb) |symb| {
                        newProd.RHS = newProd.RHS ++ .{symb};
                    } else {
                        @compileError(std.fmt.comptimePrint("Invalid symbol \"{s}\" used in production: {s}", .{ symbStr, rule }));
                    }
                    inSymb = false;
                } else {
                    // Space outside of symbol: keep looking
                    continue;
                }
            } else {
                if (inSymb) {
                    // Non-space in symbol: keep looking
                    continue;
                } else {
                    // Non-space out of symbol: start of new symbol
                    symbolStart = charInd;
                    inSymb = true;
                }
            }
        }
        if (inSymb) {
            const symbStr = rule[symbolStart..];
            const optSymb = Symbol.fromStr(symbStr);
            if (optSymb) |symb| {
                newProd.RHS = newProd.RHS ++ .{symb};
            } else {
                @compileError(std.fmt.comptimePrint("Invalid symbol \"{s}\" used in production: {s}", .{ symbStr, rule }));
            }
        }

        productions = productions ++ .{newProd};
    }

    return productions;
}

/// Makes sure that InTokenKind is actually an Enum and has EOF and NOTOKEN in the proper spots.
fn validateTokenKind(comptime TokenKind: type) void {
    const inTypeInfo: std.builtin.Type = @typeInfo(TokenKind);

    if (inTypeInfo != .Enum) {
        @compileError("TokenKind must be an enum!");
    }

    const inFields = inTypeInfo.Enum.fields;

    if (!std.mem.eql(u8, inFields[0].name, "EOF")) {
        @compileError("The first member of the TokenKind enum must have name 'EOF', for use inside the compiler");
    }

    for (inFields, 0..) |field, fieldInd| {
        if (field.value != fieldInd) {
            @compileError("Bruh don't change the enum backing value for TokenKind");
        }
    }

    const getRegexErr = "The TokenKind enum must have a 'pub fn getRegex(TokenKind) [:0]const u8' declared.\n" ++
        "This function should maps each type of token found in an input file to a regex describing that token\n";
    if (!std.meta.hasFn(TokenKind, "getRegex")) {
        @compileError(getRegexErr);
    }

    const getRegexType = @TypeOf(@field(TokenKind, "getRegex"));

    if (getRegexType != *const fn (TokenKind) [:0]const u8) {
        if (@typeInfo(getRegexType).Fn.params[0].type orelse void == TokenKind) {
            return;
        }
        @compileError(std.fmt.comptimePrint("TokenKind.getRegex must be of type 'fn(TokenKind) [:0]const u8'. Got: {any}", .{getRegexType}));
    }

    // yay!
}

fn validateNoNamingConflicts(comptime TokenKind: type, comptime NonTerminalSymbolKind: type) void {
    for (@typeInfo(TokenKind).Enum.fields, 0..) |tokenField, i| {
        for (@typeInfo(NonTerminalSymbolKind).Enum.fields[i..]) |nonTermField| {
            if (std.mem.eql(u8, tokenField.name, nonTermField.name)) {
                @compileError(std.fmt.comptimePrint("Error! Found a non-terminal symbol with the same name as a token: {s}.\nReminder that tokens cannot appear on the left hand side of a production, as they are terminal symbols.\nPlease change one of the two names.", .{tokenField.name}));
            }
        }
    }
}

/// Creates the NonTerminalSymbolKind enum
/// Also checks and ensures that every rule has exactly one non terminal on the LHS,
///    and that all rules have an arrow.
fn CreateNonTerminalSymbolEnum(comptime InputProduction: type, comptime inputGrammar: []const InputProduction) type {
    @setEvalBranchQuota(100000);
    var nonTermNames: [inputGrammar.len][:0]const u8 = undefined;
    var nonTermNum: usize = 0;

    for (inputGrammar, 0..) |rule, prodInd| {
        const str = rule.rule;

        var arrowStart: usize = 0;

        for (str, 0..) |char, i| {
            if (char == '-' and i != str.len - 1 and str[i + 1] == '>') {
                arrowStart = i;
                break;
            }
        } else {
            // We never broke. Never found an arrow
            @compileError(std.fmt.comptimePrint("Production {d}: |{s}| is missing an arrow.\nProductions should be of the form: |A -> ...|", .{ prodInd, str }));
        }

        // Inclusive
        var lastNonTermChar: usize = arrowStart - 1;

        while (lastNonTermChar > 0 and str[lastNonTermChar] == ' ') {
            lastNonTermChar -= 1;
        }

        if (lastNonTermChar == 0 and str[0] == ' ') {
            @compileError(std.fmt.comptimePrint("Production {d}: |{s}| has no non-terminal symbol on its left hand side.\nProductions should be of the form: |A -> ...|", .{ prodInd, str }));
        }

        //Inclusive
        var firstNonTermChar: usize = lastNonTermChar;
        while (firstNonTermChar > 0 and str[firstNonTermChar] != ' ') {
            firstNonTermChar -= 1;
        }

        if (str[firstNonTermChar] == ' ') {
            firstNonTermChar += 1;
        }

        var i: usize = 0;
        while (i < firstNonTermChar) {
            if (str[i] != ' ') {
                @compileError(std.fmt.comptimePrint("Production {d}: |{s}| has multiple symbols on its left hand side.\nProductions should be of the form: |A -> ...|", .{ prodInd, str }));
            }
            i += 1;
        }

        const nonTermName = str[firstNonTermChar..(lastNonTermChar + 1)];

        for (0..nonTermNum) |existingNonTermInd| {
            if (std.mem.eql(u8, nonTermNames[existingNonTermInd], nonTermName)) {
                break;
            }
        } else {
            // We didn't break. New name time
            nonTermNames[nonTermNum] = &addZ(nonTermName.len, nonTermName);
            nonTermNum += 1;
        }
    }

    var fields: [nonTermNum]EnumField = undefined;
    for (0..nonTermNum) |i| {
        fields[i] = EnumField{ .name = nonTermNames[i], .value = i };
    }

    const enumInfo = std.builtin.Type.Enum{
        .tag_type = std.math.IntFittingRange(0, nonTermNum),
        .fields = &fields,
        .decls = &[0]std.builtin.Type.Declaration{},
        .is_exhaustive = true,
    };

    return @Type(std.builtin.Type{ .Enum = enumInfo });
}
pub fn addZ(comptime length: usize, value: []const u8) [length:0]u8 {
    var terminated_value: [length:0]u8 = undefined;
    terminated_value[length] = 0;
    @memcpy(&terminated_value, value);
    return terminated_value;
}

// --- Tests ---

test "Create Non-Terminal Enum" {
    const fakeProd = struct { rule: [:0]const u8 };

    const fakeGrammar = [_]fakeProd{ .{ .rule = "A -> B C D" }, .{ .rule = "B -> A" }, .{ .rule = "A -> C" }, .{ .rule = "D ->" } };

    const NonTermType = comptime CreateNonTerminalSymbolEnum(fakeProd, &fakeGrammar);

    comptime var fieldNames: [@typeInfo(NonTermType).Enum.fields.len][]const u8 = undefined;
    comptime for (@typeInfo(NonTermType).Enum.fields, 0..) |enumField, i| {
        fieldNames[i] = enumField.name;
    };

    // const correctEnum = enum { A, B, D };
    //     // print("Generated enum:\n", .{});
    // for (fieldNames) |enumField| {
    //     // print("    {s}\n", .{enumField});
    // }
}

test "type equality" {
    const t1 = struct {
        ABC: u8,
        DEF: u16,
    };

    const t2 = t1;

    const a: t1 = .{ .ABC = 2, .DEF = 4 };

    const b: t2 = a;
    _ = b;

    // print("{}\n", .{t1 == t2});
    // print("{}\n", .{b});
}

test "production generation" {
    const t_TokenKind = enum {
        const t_TokenKind = @This();

        EOF,
        ID,
        NUM,

        pub fn getRegex(tok: t_TokenKind) [:0]const u8 {
            return switch (tok) {
                .NUM => "[0-9]*",
                .ID => "[a-zA-Z]*",
                else => "",
            };
        }
    };

    const t_Token = Token(t_TokenKind);
    const t_Production = t_Token.Production(void);
    const fakeGrammar = [_]t_Production{ .{ .rule = "A -> B ID D", .semanticAction = undefined }, .{ .rule = "B -> A", .semanticAction = undefined }, .{ .rule = "A -> NUM", .semanticAction = undefined }, .{ .rule = "D ->", .semanticAction = undefined } };
    const t_Specification = t_Production.CreateSpecification(&fakeGrammar, .{});
    _ = t_Specification;

    // std.debug.assert(t_Specification.grammar[3].eql(t_Specification.Production{ .LHS = .D, .RHS = &.{}, .semanticAction = undefined }));

    // for (t_Specification.grammar) |prod| {
    //     prod.debugPrint();
    //     print("\n", .{});
    // }
}
