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
TODO

## Usage
TODO

