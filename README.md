# Zacc: Zig-Assisted Compiler Compiler
Zacc is a compiler creation tool aiming to have similar functionality to have tools like Yacc,
 from which it obviously derives inspiration for its name.

It offers all the standard pieces of functionality expected of a compiler creation tool, with the key ones being:
1. The ability to define lexical tokens via regex.
2. The ability to lex a file into a list of tokens.
3. The ability to generate an LALR(1) parser with user-defined semantic actions.
4. The ability to pass return values semantic actions to future semantic actions that use non-terminal symbols.

What makes Zacc unique is that it's written in Zig. When you create a compiler with Zacc, all the work needed to generate the lexing and parsing tables is done at comptime.
As a result, all you need to do is type `zig build run`, and your compiler will be created and can be used. 
There's no need to install a cli tool to compile your compiler, you just build and run like it's any ordinary zig project, and there's no overhead at startup after the build is complete.

## Installation

## Usage

This is a high level guide that assumes you have read a decent amount on compilers. For example usage, see the `tests/straightline` directory of this repo.

Before continuing on, make sure you import Zacc. 
In all following code, assume `const Zacc = @import("zacc")` has already been called.

### 1. Create the data structures for the valid tokens in your language

There are two steps to this:
1. Creating an enum where each member of the enum is a kind of token that can appear in source code.
2. Give that enum to Zacc to generate a token struct that will be outputted by the lexer.
The Token struct will contain both the enum and relevant information from the source file.

Things to know about the token kind enum:
- It must have a function whose signature is **exactly**: `pub fn getRegex(self: YOUR_ENUM_TYPE_HERE) [:0]const u8`. This function should return a regex specifying what types of strings match to the enum passed into it.
- The first member of this enum must be named `EOF`. Standing for "end of file", this is a token that all languages must contain. It is required to be used at least once in a production where the left side nonterminal is a valid program/file. The regex returned for this token will be ignored.
- The enum member names `LINE_COMMENT_START`, `BLOCK_COMMENT_START`, and `BLOCK_COMMENT_END` are reserved keywords. They are required to use Zacc's builtin support for comments, and cannot be used in any productions. Regexes specified (in the getRegex function) for these members are used to determine when a comment starts or ends.
- **Order matters in this enum!**
Members that come before other members (i.e. members with a lower backing int) will be prioritized when two or more regexes match the same token. This means that you should place your keywords, for example, before your identifier token, so that 'if' does not get lexed into an identifier.

<details>
<summary>Example Token Kind Enum</summary>

```zig
const TokenKind = enum {
    EOF,
    PRINT,
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

    pub fn getRegex(self: TokenKind) [:0]const u8 {
        return switch (self) {
            .EOF => "",
            .PRINT => "print",
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
        };
    }
};
```
</details>

To create the Token struct, simply run `const Token = Zacc.specificationGenerator.Token(YOUR_ENUM_TYPE_HERE)`.

This will return a type which is a struct that looks (basically) like this:
```zig
struct {

    kind: YOUR_ENUM_TYPE_HERE,
    src: []const u8,

    pub fn Production(comptime SemanticDataType: type) type { ... }
}

```

As previously stated, the lexer that Zacc builds will convert a file into a list of these Token structs.

### 2. Create your productions

Zacc creates a semantic action-based parser, which means you get to specify the productions that the parser will follow and the functions that get executed when the parser reduces by one of your productions.

Eventually, your list of productions will look like a list of `Production` (or whatever name you decide on) structs.
Each struct will have a string specifying the production itself, and a function pointer pointing to a semantic action associated with that production.

To create this Production struct type, Zacc needs to know the type of the function pointer, which means it needs to understand what the inputs and outputs of a semantic action are, in your compiler.

Because of this, all semantic actions must have the same return type, which, in most real applications, will most likely be a tagged union, probably representing a node in your AST.

By enforcing this constraint, Zacc is able to associate the return value of a semantic action with a specific nonterminal symbol.
The return value can be (and is) stored on a stack and eventually passed as input to a future semantic action.

Once you have created this type that your semantic actions return (I'd reccommend starting with an incomplete type and adding onto it as you implement actions), you can use it, and the Token type, to generate the actual Production struct.

Do this by calling `const Production = Token.Production(YOUR_SEMANTIC_DATA_TYPE_HERE);`

This returns the previously described type, which looks something like this:
```zig
struct {
    pub const SymbolData = union(enum) { token: Token, semanticData: YOUR_SEMANTIC_DATA_TYPE_HERE };

    rule: [:0]const u8,
    semanticAction: *const fn ([]SymbolData) SemanticDataType,

    pub fn CreateSpecification(comptime grammar: []const Production_, comptime options: CompilationOptions) type { ... }
}
```

Please note the `SymbolData` tagged union. This is what your semantic actions must take as input.

Specifically, your actions must take a slice of those unions, where the slice passed in will be of equal length to the right-hand side (RHS) of your production.
For every element in the slice:
- If the matching symbol in the production rhs is terminal, the tagged union will have the token field active, and will give you the token outputted by the lexer.
- If the matching symbol in the production rhs is non-terminal, that union will have the semanticData field active, and will give you an item of your semantic data type. This item will have been returned by your previous semantic actions.

Knowing this, you should now create an array of Production structs with your actions and rules.
This is the final required step before creating the compiler.

Notes on making rules:
- Rules should be of the form "NONTERMINAL -> SYMB_A SYMB_B ..."
- To use Tokens in your rules, use the enum member name. So, if your enum had members "IDENTIFIER" and "PLUS
 you could make a rule like "ADD -> IDENTIFIER PLUS IDENTIFIER"
- The first rule(s) you create must be of the form "A -> B C D ... Y Z EOF". Reducing by this/these rule(s) signals the complete parsing of a file, and will cause the parser to accept the input and stop parsing. The compiler will return the return value of the semantic action(s) associated with this/these rule(s) upon successfully compiling a file.

<details>
<summary>Example</summary>

```zig
pub const ProductionActions = @import("actions/productionActions.zig");
pub const OperatorActions = @import("actions/operatorActions.zig");
pub const SymbolActions = @import("actions/symbolActions.zig");

pub const SemanticData = f64;

const Production = Token.Production(SemanticData);

// Public so that it can be used when defining semantic actions in the other files.
pub const SymbolData: type = Production.SymbolData;

const grammar: []const Production = &[_]Production{
    .{ .rule = "PROGRAM -> SPRIME EOF", .semanticAction = ProductionActions.doNothing },
    .{ .rule = "SPRIME -> S SEMICOLON", .semanticAction = ProductionActions.doNothing },
    .{ .rule = "SPRIME -> SPRIME S SEMICOLON", .semanticAction = ProductionActions.doNothing },
    .{ .rule = "S -> PRINT L_PAREN E R_PAREN", .semanticAction = ProductionActions.print },
    .{ .rule = "S -> ID L_ASSIGN E", .semanticAction = SymbolActions.leftAssignVariable },
    .{ .rule = "S -> E R_ASSIGN ID", .semanticAction = SymbolActions.rightAssignVariable },
    .{ .rule = "E -> E PLUS T", .semanticAction = OperatorActions.add },
    .{ .rule = "E -> E MINUS T", .semanticAction = OperatorActions.sub },
    .{ .rule = "E -> T", .semanticAction = ProductionActions.percolateFloat },
    .{ .rule = "T -> T MULT F", .semanticAction = OperatorActions.mul },
    .{ .rule = "T -> T DIV F", .semanticAction = OperatorActions.div },
    .{ .rule = "T -> F", .semanticAction = ProductionActions.percolateFloat },
    .{ .rule = "F -> ID", .semanticAction = SymbolActions.fetchValue },
    .{ .rule = "F -> NUM", .semanticAction = ProductionActions.parseFloat },
    .{ .rule = "F -> MINUS NUM", .semanticAction = OperatorActions.negate },
    .{ .rule = "F -> L_PAREN E R_PAREN", .semanticAction = ProductionActions.percolateFloatParens },
};
```
</details>

### 3. Create your compiler!

Finally we can create a language specification: a struct from which Zacc can create a compiler!

We need our grammar created in the previous step, and we have the option to specify any additional settings for the compiler, via the `Zacc.specificationGenerator.CompilationOptions` struct, which looks like:
```zig
pub const CompilationOptions = struct {
    /// Enables the verbose lexing debugging feature.
    /// Prints each character and matched tokens to stderr.
    verboseLexing: bool = false,
    /// Enables the verbose parsing debugging feature.
    /// Prints each input token and all shift/reduce actions taken.
    verboseParsing: bool = false,
    /// Can block comments be nested?
    supportNestedBlockComments: bool = false,
    /// Characters that the compiler ignores.
    /// These characters cannot be used in tokens or comment delimiters.
    /// Code surrounded by these characters must be a sequence of valid tokens.
    whitespaceCharacters: []const u8 = &.{ ' ', '\n', '\t', '\r' },
};
```

To create the spec, simply call `const Specification = Production.CreateSpecification(grammar, .{});` (where the second parameter is a CompilationOptions struct).
This is a function in your Production type.

Then, to create the compiler, call `const Compiler = Zacc.Compiler(Specification);`, and you are ready to go!

To use it, just call `Compiler.compileStdFsFile(inFile, std.testing.allocator);`, where inFile is a std.fs.File.

This function returns your semantic data type as previously described (or an error).

