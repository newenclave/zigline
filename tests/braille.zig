const std = @import("std");
const braille = @import("zigline").braille;

test "Braille cells map dots to their Unicode bit positions" {
    var scene: braille.StaticScene(2, 4) = .{};

    try std.testing.expect(scene.setDot(0, 0));
    try std.testing.expect(scene.setDot(1, 3));
    try std.testing.expectEqual(@as(?u8, 0x81), scene.cellAt(0, 0));
    try std.testing.expectEqual(@as(u32, 0x2881), braille.toUnicode(scene.cellAt(0, 0).?));

    try std.testing.expect(scene.cleanDot(0, 0));
    try std.testing.expectEqual(@as(?u8, 0x80), scene.cellAt(0, 0));
}

test "StaticScene rounds dot dimensions up to Braille cells" {
    const Scene = braille.StaticScene(3, 5);

    try std.testing.expectEqual(@as(usize, 2), Scene.width_in_cells);
    try std.testing.expectEqual(@as(usize, 2), Scene.height_in_cells);
}

test "Scenes reject dots and cells outside their bounds" {
    var static_scene: braille.StaticScene(2, 4) = .{};
    try std.testing.expect(!static_scene.setDot(2, 0));
    try std.testing.expect(!static_scene.setDot(0, 4));
    try std.testing.expectEqual(@as(?u8, 0), static_scene.cellAt(0, 0));
    try std.testing.expectEqual(@as(?u8, null), static_scene.cellAt(1, 0));

    var dynamic_scene = try braille.DynamicScene.init(std.testing.allocator, 3, 5);
    defer dynamic_scene.deinit();

    try std.testing.expectEqual(@as(usize, 2), dynamic_scene.width_in_cells);
    try std.testing.expectEqual(@as(usize, 2), dynamic_scene.height_in_cells);
    try std.testing.expect(dynamic_scene.setDot(2, 4));
    try std.testing.expectEqual(@as(?u8, 0x01), dynamic_scene.cellAt(1, 1));
    try std.testing.expect(!dynamic_scene.cleanDot(3, 4));
}
