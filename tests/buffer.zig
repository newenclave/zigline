const std = @import("std");
const zigline = @import("zigline");
const Buffer = zigline.Buffer;

fn expect(b: *const Buffer, content: []const u8, cursor: usize) !void {
    try std.testing.expectEqualStrings(content, b.items());
    try std.testing.expectEqual(cursor, b.cursor);
}

test "Buffer: insert advances cursor" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("abc");
    try expect(&b, "abc", 3);
}

test "Buffer: insert in the middle" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("abc");
    b.moveLeft();
    b.moveLeft();
    try b.insertByte('X');
    try expect(&b, "aXbc", 2);
}

test "Buffer: backspace and clamp at start" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("abc");
    b.backspace();
    try expect(&b, "ab", 2);
    b.moveHome();
    b.backspace(); // no-op at start
    try expect(&b, "ab", 0);
}

test "Buffer: deleteForward and clamp at end" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("abc");
    b.moveHome();
    b.deleteForward();
    try expect(&b, "bc", 0);
    b.moveEnd();
    b.deleteForward(); // no-op at end
    try expect(&b, "bc", 2);
}

test "Buffer: home and end" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("hello");
    b.moveHome();
    try std.testing.expectEqual(@as(usize, 0), b.cursor);
    b.moveEnd();
    try std.testing.expectEqual(@as(usize, 5), b.cursor);
}

test "Buffer: move clamps at both ends" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("ab");
    b.moveLeft();
    b.moveLeft();
    b.moveLeft();
    try std.testing.expectEqual(@as(usize, 0), b.cursor);
    b.moveRight();
    b.moveRight();
    b.moveRight();
    try std.testing.expectEqual(@as(usize, 2), b.cursor);
}

test "Buffer: deleteToEnd" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("hello world");
    b.cursor = 5;
    b.deleteToEnd();
    try expect(&b, "hello", 5);
}

test "Buffer: deleteToStart" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("hello world");
    b.cursor = 6;
    b.deleteToStart();
    try expect(&b, "world", 0);
}

test "Buffer: set replaces content and moves cursor to end" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("abc");
    b.moveHome();
    try b.set("longer line");
    try expect(&b, "longer line", 11);
}

test "Buffer: toOwnedSlice copies content" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("copy me");
    const owned = try b.toOwnedSlice();
    defer std.testing.allocator.free(owned);
    try std.testing.expectEqualStrings("copy me", owned);
}

test "Buffer: moveLeft/moveRight step by whole UTF-8 codepoints" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("a€b"); // 'a'=1 byte, '€'=3 bytes, 'b'=1 byte; len=5
    try std.testing.expectEqual(@as(usize, 5), b.cursor);
    b.moveLeft(); // over 'b'
    try std.testing.expectEqual(@as(usize, 4), b.cursor);
    b.moveLeft(); // over '€' (3 bytes at once)
    try std.testing.expectEqual(@as(usize, 1), b.cursor);
    b.moveLeft(); // over 'a'
    try std.testing.expectEqual(@as(usize, 0), b.cursor);
    b.moveRight(); // over 'a'
    try std.testing.expectEqual(@as(usize, 1), b.cursor);
    b.moveRight(); // over '€'
    try std.testing.expectEqual(@as(usize, 4), b.cursor);
}

test "Buffer: backspace removes a whole multibyte codepoint" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("café"); // 'é' = 2 bytes (0xC3 0xA9)
    b.backspace(); // removes 'é' entirely
    try expect(&b, "caf", 3);
    try b.insertSlice("é😀"); // add 2-byte and 4-byte codepoints
    b.backspace(); // removes 😀 (4 bytes)
    try expect(&b, "café", 5);
}

test "Buffer: deleteForward removes the whole codepoint at the cursor" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("a€b");
    b.moveHome();
    b.deleteForward(); // removes 'a'
    try expect(&b, "€b", 0);
    b.deleteForward(); // removes '€' (3 bytes)
    try expect(&b, "b", 0);
}

test "Buffer: cursor stays on a boundary so toOwnedSlice yields valid UTF-8" {
    var b = Buffer.init(std.testing.allocator);
    defer b.deinit();
    try b.insertSlice("Äilöä Väilöä Бла бла"); // contains multibyte codepoints
    b.moveLeft();
    b.moveLeft();
    b.backspace();
    const owned = try b.toOwnedSlice();
    defer std.testing.allocator.free(owned);
    try std.testing.expect(std.unicode.utf8ValidateSlice(owned));
}
