const std = @import("std");
const tokenize = @import("zigline").tokenize;

fn expectTokens(input: []const u8, expected: []const []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const got = try tokenize(arena.allocator(), input);
    try std.testing.expectEqual(expected.len, got.len);
    for (expected, got) |e, g| {
        try std.testing.expectEqualStrings(e, g);
    }
}

test "Tokenize: simple whitespace split" {
    try expectTokens("mk test_dir", &.{ "mk", "test_dir" });
}

test "Tokenize: leading, trailing and repeated whitespace" {
    try expectTokens("  leading\tand   trailing  ", &.{ "leading", "and", "trailing" });
}

test "Tokenize: empty input yields no tokens" {
    try expectTokens("", &.{});
    try expectTokens("   \t  ", &.{});
}

test "Tokenize: double quotes preserve spaces" {
    try expectTokens("echo \"a b\" c", &.{ "echo", "a b", "c" });
}

test "Tokenize: single quotes are literal" {
    try expectTokens("echo 'a b' c", &.{ "echo", "a b", "c" });
    try expectTokens("'\\n stays literal'", &.{"\\n stays literal"});
}

test "Tokenize: backslash escapes outside quotes" {
    try expectTokens("a\\ b", &.{"a b"});
    try expectTokens("\\\"quoted\\\"", &.{"\"quoted\""});
}

test "Tokenize: backslash escapes inside double quotes" {
    try expectTokens("\"a\\\"b\"", &.{"a\"b"});
}

test "Tokenize: empty quoted string is an empty token" {
    try expectTokens("a \"\" b", &.{ "a", "", "b" });
}

test "realistic command line" {
    try expectTokens("git commit -m \"msg here\"", &.{ "git", "commit", "-m", "msg here" });
}

test "Tokenize: unterminated quote is an error" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.UnterminatedQuote, tokenize(arena.allocator(), "\"oops"));
    try std.testing.expectError(error.UnterminatedQuote, tokenize(arena.allocator(), "'oops"));
}

test "Tokenize: trailing backslash is an unterminated escape" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.UnterminatedEscape, tokenize(arena.allocator(), "abc\\"));
    try std.testing.expectError(error.UnterminatedEscape, tokenize(arena.allocator(), "\"abc\\"));
}
