const std = @import("std");
const Io = std.Io;
const History = @import("zigline").History;

test "History: add preserves order and count" {
    var h = History.init(std.testing.allocator, 16);
    defer h.deinit();
    try h.add("a");
    try h.add("b");
    try h.add("c");
    try std.testing.expectEqual(@as(usize, 3), h.count());
    try std.testing.expectEqualStrings("a", h.get(0));
    try std.testing.expectEqualStrings("c", h.get(2));
}

test "History: empty lines are ignored" {
    var h = History.init(std.testing.allocator, 16);
    defer h.deinit();
    try h.add("");
    try std.testing.expectEqual(@as(usize, 0), h.count());
}

test "History: consecutive duplicates are ignored, non-consecutive kept" {
    var h = History.init(std.testing.allocator, 16);
    defer h.deinit();
    try h.add("a");
    try h.add("a");
    try std.testing.expectEqual(@as(usize, 1), h.count());
    try h.add("b");
    try h.add("a");
    try std.testing.expectEqual(@as(usize, 3), h.count());
}

test "History: capacity evicts oldest" {
    var h = History.init(std.testing.allocator, 2);
    defer h.deinit();
    try h.add("a");
    try h.add("b");
    try h.add("c");
    try std.testing.expectEqual(@as(usize, 2), h.count());
    try std.testing.expectEqualStrings("b", h.get(0));
    try std.testing.expectEqualStrings("c", h.get(1));
}

test "History: up/down navigation" {
    var h = History.init(std.testing.allocator, 16);
    defer h.deinit();
    try h.add("a");
    try h.add("b");
    try h.add("c");

    // Fresh line: down does nothing.
    try std.testing.expectEqual(@as(?[]const u8, null), h.down());

    try std.testing.expectEqualStrings("c", h.up().?);
    try std.testing.expectEqualStrings("b", h.up().?);
    try std.testing.expectEqualStrings("a", h.up().?);
    try std.testing.expectEqualStrings("a", h.up().?); // clamped at oldest

    try std.testing.expectEqualStrings("b", h.down().?);
    try std.testing.expectEqualStrings("c", h.down().?);
    try std.testing.expectEqual(@as(?[]const u8, null), h.down()); // back to fresh line
}

test "History: up on empty history is null" {
    var h = History.init(std.testing.allocator, 16);
    defer h.deinit();
    try std.testing.expectEqual(@as(?[]const u8, null), h.up());
}
