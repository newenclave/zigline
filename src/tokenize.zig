const std = @import("std");

const Quote = enum {
    none,
    single,
    double,
};

pub const Error = error{ UnterminatedQuote, UnterminatedEscape } ||
    std.mem.Allocator.Error;

const Chars = enum(u8) {
    space = ' ',
    tab = '\t',
    carriage_return = '\r',
    newline = '\n',
    single_quote = '\'',
    double_quote = '"',
    backslash = '\\',
};

pub fn tokenize(arena: std.mem.Allocator, input: []const u8) Error![][]u8 {
    var tokens: std.ArrayList([]u8) = .empty;
    var cur: std.ArrayList(u8) = .empty;
    defer cur.deinit(arena);

    var in_token = false;
    var quote: Quote = .none;

    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        switch (quote) {
            .single => switch (c) {
                '\'' => quote = .none,
                else => try cur.append(arena, c),
            },
            .double => switch (c) {
                '"' => quote = .none,
                '\\' => {
                    i += 1;
                    if (i >= input.len) {
                        return Error.UnterminatedEscape;
                    }
                    try cur.append(arena, input[i]);
                },
                else => try cur.append(arena, c),
            },
            .none => switch (c) {
                ' ', '\t', '\r', '\n' => {
                    if (in_token) {
                        try tokens.append(arena, try cur.toOwnedSlice(arena));
                        in_token = false;
                    }
                    continue;
                },
                '\'' => quote = .single,
                '"' => quote = .double,
                '\\' => {
                    i += 1;
                    if (i >= input.len) {
                        return Error.UnterminatedEscape;
                    }
                    try cur.append(arena, input[i]);
                },
                else => try cur.append(arena, c),
            },
        }
        in_token = true;
    }

    if (quote != .none) {
        return Error.UnterminatedQuote;
    }
    if (in_token) {
        try tokens.append(arena, try cur.toOwnedSlice(arena));
    }

    return tokens.toOwnedSlice(arena);
}
