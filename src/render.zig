//!
//! render.zig - Render for line editing
//!
//! @author
//!     newenclave
//! @license
//!     MIT
//! @see
//!     github.com/newenclave/zigline
//!
const std = @import("std");
const Io = std.Io;

pub fn renderLine(w: *Io.Writer, prompt: []const u8, items: []const u8, cursor: usize) Io.Writer.Error!void {
    try w.writeAll("\r");
    try w.writeAll(prompt);
    try w.writeAll(items);
    try w.writeAll("\x1b[K");
    const tail = items[cursor..];
    const back = std.unicode.utf8CountCodepoints(tail) catch tail.len;
    if (back > 0) {
        try w.print("\x1b[{d}D", .{back});
    }
}
