//! Generic lifecycle contract for renderers that react to terminal cells.
const std = @import("std");

pub fn Renderer(comptime Context: type) type {
    return struct {
        /// Errors returned by the renderer's lifecycle methods.
        pub const Error = error{};

        /// Prepares the renderer before the first visible cell is written.
        pub fn beginRender(_: *Context, _: *std.Io.Writer) Error!void {}

        /// Updates output state before a visible cell is written. `glyph` is temporary.
        pub fn beforeCell(
            _: *Context,
            _: *std.Io.Writer,
            _: usize,
            _: usize,
            _: []const u8,
        ) Error!void {}

        /// Finishes the renderer after the final visible cell is written.
        pub fn endRender(_: *Context, _: *std.Io.Writer) Error!void {}
    };
}
