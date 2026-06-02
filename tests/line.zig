const std = @import("std");
const Io = std.Io;
const Line = @import("zigline").Line;
const renderLine = @import("zigline").renderLine;
const terminal = @import("zigline").terminal;
const Buffer = @import("zigline").Buffer;

test "Line: renderLine with cursor at end" {
    var out: [128]u8 = undefined;
    var w = Io.Writer.fixed(&out);
    try renderLine(&w, "> ", "abc", 3);
    try std.testing.expectEqualStrings("\r> abc\x1b[K", w.buffered());
}

test "Line: renderLine with cursor in the middle moves cursor back" {
    var out: [128]u8 = undefined;
    var w = Io.Writer.fixed(&out);
    try renderLine(&w, "> ", "abc", 1);
    try std.testing.expectEqualStrings("\r> abc\x1b[K\x1b[2D", w.buffered());
}

test "Line: renderLine with empty buffer" {
    var out: [128]u8 = undefined;
    var w = Io.Writer.fixed(&out);
    try renderLine(&w, "$ ", "", 0);
    try std.testing.expectEqualStrings("\r$ \x1b[K", w.buffered());
}

test "Line: renderLine moves back by codepoints, not bytes" {
    // "a€b" is 5 bytes but 3 codepoints; cursor after 'a€' (byte 4) leaves one
    // codepoint ('b') to the right, so the cursor moves back 1 column, not 1 byte.
    var out: [128]u8 = undefined;
    var w = Io.Writer.fixed(&out);
    try renderLine(&w, "> ", "a€b", 4);
    try std.testing.expectEqualStrings("\r> a€b\x1b[K\x1b[1D", w.buffered());
}

test "Line: cooked-mode read splits on newlines and reports EOF" {
    var ed = Line.init(std.testing.allocator, undefined, .{ .prompt = "> " });
    defer ed.deinit();

    var out: [256]u8 = undefined;
    var w = Io.Writer.fixed(&out);
    var r = Io.Reader.fixed("hello\nwith\ttabs\r\n");

    const l1 = (try ed.readLineCooked(&w, &r)).?;
    defer std.testing.allocator.free(l1);
    try std.testing.expectEqualStrings("hello", l1);

    const l2 = (try ed.readLineCooked(&w, &r)).?; // \r stripped, line ends at \n
    defer std.testing.allocator.free(l2);
    try std.testing.expectEqualStrings("with\ttabs", l2);

    // Nothing left: clean EOF returns null.
    try std.testing.expectEqual(@as(?[]u8, null), try ed.readLineCooked(&w, &r));
}

test "Line: cooked-mode returns a trailing line with no final newline" {
    var ed = Line.init(std.testing.allocator, undefined, .{});
    defer ed.deinit();

    var out: [64]u8 = undefined;
    var w = Io.Writer.fixed(&out);
    var r = Io.Reader.fixed("partial");

    const l = (try ed.readLineCooked(&w, &r)).?;
    defer std.testing.allocator.free(l);
    try std.testing.expectEqualStrings("partial", l);
}
