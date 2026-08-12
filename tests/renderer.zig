const std = @import("std");
const Io = std.Io;

const TestEvent = enum {
    begin,
    cell,
    end,
};

const RecordingContext = struct {
    events: [4]TestEvent = undefined,
    event_count: usize = 0,
    glyphs: [2][3]u8 = undefined,
    glyph_count: usize = 0,

    fn record(self: *@This(), event: TestEvent) void {
        self.events[self.event_count] = event;
        self.event_count += 1;
    }
};

const RecordingRenderer = struct {
    pub const Error = error{};

    pub fn beginRender(context: *RecordingContext, _: *std.Io.Writer) Error!void {
        context.record(.begin);
    }

    pub fn beforeCell(
        context: *RecordingContext,
        _: *std.Io.Writer,
        _: usize,
        _: usize,
        glyph: []const u8,
    ) Error!void {
        context.record(.cell);
        @memcpy(context.glyphs[context.glyph_count][0..glyph.len], glyph);
        context.glyph_count += 1;
    }

    pub fn endRender(context: *RecordingContext, _: *std.Io.Writer) Error!void {
        context.record(.end);
    }
};

test "renderer lifecycle surrounds visible glyphs" {
    var output: [16]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output);
    var context: RecordingContext = .{};

    try RecordingRenderer.beginRender(&context, &writer);
    try RecordingRenderer.beforeCell(&context, &writer, 0, 0, "\xe2\xa0\x81");
    try writer.writeAll("\xe2\xa0\x81");
    try RecordingRenderer.beforeCell(&context, &writer, 1, 0, "\xe2\xa0\x82");
    try writer.writeAll("\xe2\xa0\x82");
    try RecordingRenderer.endRender(&context, &writer);

    try std.testing.expectEqualSlices(TestEvent, &.{ .begin, .cell, .cell, .end }, context.events[0..context.event_count]);
    try std.testing.expectEqualStrings("\xe2\xa0\x81", &context.glyphs[0]);
    try std.testing.expectEqualStrings("\xe2\xa0\x82", &context.glyphs[1]);
    try std.testing.expectEqualStrings("\xe2\xa0\x81\xe2\xa0\x82", writer.buffered());
}

const FailingContext = struct {
    began: bool = false,
    ended: bool = false,
};

const FailingRenderer = struct {
    pub const Error = error{BeforeCellFailed};

    pub fn beginRender(context: *FailingContext, _: *std.Io.Writer) Error!void {
        context.began = true;
    }

    pub fn beforeCell(_: *FailingContext, _: *std.Io.Writer, _: usize, _: usize, _: []const u8) Error!void {
        return error.BeforeCellFailed;
    }

    pub fn endRender(context: *FailingContext, _: *std.Io.Writer) Error!void {
        context.ended = true;
    }
};

test "renderer reports beforeCell failures" {
    var output: [16]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output);
    var context: FailingContext = .{};

    try FailingRenderer.beginRender(&context, &writer);
    try std.testing.expectError(
        error.BeforeCellFailed,
        FailingRenderer.beforeCell(&context, &writer, 0, 0, "\xe2\xa0\x81"),
    );
    try std.testing.expect(context.began);
    try std.testing.expect(!context.ended);
}
