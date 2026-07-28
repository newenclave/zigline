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

    try out.writeAll("zigline demo REPL\r\n\n");
    try out.flush();

    var editor = zigline.Line.init(gpa, io, .{ .prompt = "zigline> " });
    defer editor.deinit();
    var raw = try terminal.RawMode.enable();
    defer raw.disable();

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
            try out.print("  [{d}] '{s}'\r\n", .{ i, tok });
        }
        try out.flush();

        try editor.historyAdd(line);
    }

    try out.writeAll("noniin!\r\n");
    try out.flush();
}
