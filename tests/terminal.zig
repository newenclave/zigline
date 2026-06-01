const std = @import("std");
const zigline = @import("zigline");
const terminal = zigline.terminal;
const Key = terminal.Key;

const readKey = terminal.readKey;

fn decodeOne(bytes: []const u8) !Key {
    var r = std.Io.Reader.fixed(bytes);
    return readKey(&r);
}

test "Terminal: printable ASCII decodes to codepoint" {
    try std.testing.expectEqual(Key{ .codepoint = 'a' }, try decodeOne("a"));
    try std.testing.expectEqual(Key{ .codepoint = ' ' }, try decodeOne(" "));
}

test "Terminal: UTF-8 multibyte sequences decode to a single codepoint" {
    try std.testing.expectEqual(Key{ .codepoint = 0xE9 }, try decodeOne("é")); // 2 bytes
    try std.testing.expectEqual(Key{ .codepoint = 0x20AC }, try decodeOne("€")); // 3 bytes
    try std.testing.expectEqual(Key{ .codepoint = 0x1F636 }, try decodeOne("😶‍🌫️")); // 4 bytes

    var r = std.Io.Reader.fixed("什伵");
    try std.testing.expectEqual(Key{ .codepoint = 0x4EC0 }, try readKey(&r));
    try std.testing.expectEqual(Key{ .codepoint = 0x4F35 }, try readKey(&r));
}

test "Terminal: invalid UTF-8 lead or truncated sequence is unknown" {
    try std.testing.expectEqual(Key.unknown, try decodeOne("\x80"));
    try std.testing.expectEqual(Key.unknown, try decodeOne("\xC3"));
}

test "Terminal: enter and backspace" {
    try std.testing.expectEqual(Key.enter, try decodeOne("\r"));
    try std.testing.expectEqual(Key.enter, try decodeOne("\n"));
    try std.testing.expectEqual(Key.backspace, try decodeOne("\x7f"));
    try std.testing.expectEqual(Key.backspace, try decodeOne("\x08"));
}

test "Terminal: control keys" {
    try std.testing.expectEqual(Key.ctrl_a, try decodeOne("\x01"));
    try std.testing.expectEqual(Key.ctrl_c, try decodeOne("\x03"));
    try std.testing.expectEqual(Key.ctrl_d, try decodeOne("\x04"));
    try std.testing.expectEqual(Key.ctrl_e, try decodeOne("\x05"));
    try std.testing.expectEqual(Key.ctrl_k, try decodeOne("\x0b"));
    try std.testing.expectEqual(Key.ctrl_l, try decodeOne("\x0c"));
    try std.testing.expectEqual(Key.ctrl_u, try decodeOne("\x15"));
}

test "Terminal: CSI arrow keys" {
    try std.testing.expectEqual(Key.up, try decodeOne("\x1b[A"));
    try std.testing.expectEqual(Key.down, try decodeOne("\x1b[B"));
    try std.testing.expectEqual(Key.right, try decodeOne("\x1b[C"));
    try std.testing.expectEqual(Key.left, try decodeOne("\x1b[D"));
    try std.testing.expectEqual(Key.home, try decodeOne("\x1b[H"));
    try std.testing.expectEqual(Key.end, try decodeOne("\x1b[F"));
}

test "Terminal: CSI numbered sequences" {
    try std.testing.expectEqual(Key.delete, try decodeOne("\x1b[3~"));
    try std.testing.expectEqual(Key.home, try decodeOne("\x1b[1~"));
    try std.testing.expectEqual(Key.home, try decodeOne("\x1b[7~"));
    try std.testing.expectEqual(Key.end, try decodeOne("\x1b[4~"));
    try std.testing.expectEqual(Key.end, try decodeOne("\x1b[8~"));
}

test "Terminal: SS3 sequences" {
    try std.testing.expectEqual(Key.home, try decodeOne("\x1bOH"));
    try std.testing.expectEqual(Key.up, try decodeOne("\x1bOA"));
}

test "Terminal: bare escape and unknown sequences" {
    try std.testing.expectEqual(Key.unknown, try decodeOne("\x1b"));
    try std.testing.expectEqual(Key.unknown, try decodeOne("\x1b[Z"));
    try std.testing.expectEqual(Key.unknown, try decodeOne("\x1b[99~"));
}

test "Terminal: modified CSI sequences are fully consumed" {
    var r = std.Io.Reader.fixed("\x1b[1;2~x");
    try std.testing.expectEqual(Key.home, try readKey(&r));
    try std.testing.expectEqual(Key{ .codepoint = 'x' }, try readKey(&r));

    var r2 = std.Io.Reader.fixed("\x1b[1;5Cy");
    try std.testing.expectEqual(Key.right, try readKey(&r2));
    try std.testing.expectEqual(Key{ .codepoint = 'y' }, try readKey(&r2));
}

test "Terminal: EOF propagates as error" {
    try std.testing.expectError(error.EndOfStream, decodeOne(""));
}

test "Terminal: consecutive keys from one stream" {
    var r = std.Io.Reader.fixed("ab\x1b[Dc");
    try std.testing.expectEqual(Key{ .codepoint = 'a' }, try readKey(&r));
    try std.testing.expectEqual(Key{ .codepoint = 'b' }, try readKey(&r));
    try std.testing.expectEqual(Key.left, try readKey(&r));
    try std.testing.expectEqual(Key{ .codepoint = 'c' }, try readKey(&r));
}
