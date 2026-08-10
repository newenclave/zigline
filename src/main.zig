const std = @import("std");
const Io = std.Io;

const zigline = @import("zigline");
const terminal = zigline.terminal;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const out = &stdout_file_writer.interface;

    var raw = try terminal.RawMode.enable();
    defer raw.disable();

    try terminal.Geometry.clear();
    const size = try terminal.Geometry.size();
    const frame_width: u16 = 16;
    const frame_height: u16 = 3;
    const x = if (size.x > frame_width) (size.x - frame_width) / 2 else 0;
    const y = if (size.y > frame_height) (size.y - frame_height) / 2 else 0;

    try terminal.Geometry.setPos(x, y);
    try out.writeAll("┌──────────────┐\r\n");
    try out.flush();
    try terminal.Geometry.setPos(x, y + 1);
    try out.writeAll("│hello, zigline│\r\n");
    try out.flush();
    try terminal.Geometry.setPos(x, y + 2);
    try out.writeAll("└──────────────┘\r\n\r\n");
    try out.flush();

    const Scene = zigline.braille.StaticScene(16, 12);
    var scene: Scene = .{};
    for (0..Scene.dot_width) |dot_x| {
        _ = scene.setDot(dot_x, dot_x / 2);
        _ = scene.setDot(dot_x, Scene.dot_height - 1 - dot_x / 2);
    }
    if (y + 7 < size.y) {
        try scene.renderAt(out, x, y + 4);
        try out.flush();
        try terminal.Geometry.setPos(0, y + 7);
    }

    var editor = zigline.Line.init(gpa, io, .{ .prompt = "zigline> " });
    defer editor.deinit();

    while (try editor.readLine()) |line| {
        defer gpa.free(line);

        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();

        const tokens = zigline.tokenize(arena.allocator(), line) catch |err| {
            try out.print("parse error: {s}\n", .{@errorName(err)});
            try out.flush();
            continue;
        };

        try out.print("{d} token(s):\r\n", .{tokens.len});
        for (tokens, 0..) |tok, i| {
            try out.print("  [{d}] '", .{i});
            if (colorFor(tok)) |color| {
                try out.flush();
                try terminal.setColor(color);
                try out.writeAll(tok);
                try out.flush();
                try terminal.none();
            } else {
                try out.writeAll(tok);
            }
            try out.writeAll("'\r\n");
        }
        try out.flush();

        try editor.historyAdd(line);
    }

    try out.writeAll("noniin!\r\n");
    try out.flush();
}

fn colorFor(word: []const u8) ?terminal.Color {
    if (std.mem.eql(u8, word, "red")) return .red;
    if (std.mem.eql(u8, word, "green")) return .green;
    if (std.mem.eql(u8, word, "blue")) return .blue;
    if (std.mem.eql(u8, word, "yellow")) return .yellow;
    if (std.mem.eql(u8, word, "white") or std.mem.eql(u8, word, "light")) return .white;
    if (std.mem.eql(u8, word, "cyan")) return .cyan;
    if (std.mem.eql(u8, word, "none")) return .none;
    return null;
}
