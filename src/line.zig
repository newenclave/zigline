const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Buffer = @import("buffer.zig").Buffer;
const History = @import("history.zig").History;
const terminal = @import("terminal.zig");
const Key = terminal.Key;

const renderLine = @import("render.zig").renderLine;

pub const Line = struct {
    pub const Options = struct {
        prompt: []const u8 = "> ",
        max_history: usize = 256,
    };

    const EOL = "\r\n";
    const CLS = "\x1b[H\x1b[2J";
    const MAX_IN_BUF = 64;
    const MAX_OUT_BUF = 512;

    pub const Error = std.Io.Reader.Error ||
        std.Io.Writer.Error ||
        terminal.Error ||
        Buffer.Error ||
        History.Error;

    const Self = @This();

    gpa: Allocator,
    io: Io,
    prompt: []const u8,
    history: History,
    in_buf: [MAX_IN_BUF]u8,
    reader: ?Io.File.Reader,

    pub fn init(gpa: Allocator, io: Io, opts: Options) Self {
        return .{
            .gpa = gpa,
            .io = io,
            .prompt = opts.prompt,
            .history = History.init(gpa, opts.max_history),
            .in_buf = undefined,
            .reader = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.history.deinit();
        self.* = undefined;
    }

    pub fn historyAdd(self: *Self, line: []const u8) Error!void {
        try self.history.add(line);
    }

    pub fn historyCount(self: *const Self) usize {
        return self.history.count();
    }

    pub fn readLine(self: *Self) !?[]u8 {
        self.history.resetNav();

        var out_buf: [MAX_OUT_BUF]u8 = undefined;
        var fw = Io.File.Writer.init(Io.File.stdout(), self.io, &out_buf);
        const w = &fw.interface;

        if (self.reader == null) {
            self.reader = Io.File.Reader.init(Io.File.stdin(), self.io, &self.in_buf);
        }
        const r = &self.reader.?.interface;

        // var raw = terminal.RawMode.enable() catch {
        //     return self.readLineCooked(w, r);
        // };
        // defer raw.disable();

        return self.editLoop(w, r);
    }

    fn editLoop(self: *Self, w: *Io.Writer, r: *Io.Reader) Error!?[]u8 {
        var buf = Buffer.init(self.gpa);
        defer buf.deinit();

        try renderLine(w, self.prompt, buf.items(), buf.cursor);
        try w.flush();

        while (true) {
            const key = terminal.readKey(r) catch |e| switch (e) {
                error.EndOfStream => {
                    if (buf.len() == 0) {
                        return null;
                    }
                    break;
                },
                else => return e,
            };

            switch (key) {
                .codepoint => |cp| {
                    var tmp: [4]u8 = undefined;
                    if (std.unicode.utf8Encode(cp, &tmp)) |n| {
                        try buf.insertSlice(tmp[0..n]);
                    } else |_| {}
                },
                .enter => break,
                .backspace => buf.backspace(),
                .delete => buf.deleteForward(),
                .left => buf.moveLeft(),
                .right => buf.moveRight(),
                .home, .ctrl_a => buf.moveHome(),
                .end, .ctrl_e => buf.moveEnd(),
                .ctrl_u => buf.deleteToStart(),
                .ctrl_k => buf.deleteToEnd(),
                .ctrl_l => {
                    try w.writeAll(CLS);
                },
                .ctrl_c => {
                    try w.writeAll(EOL);
                    try w.flush();
                    return try self.gpa.dupe(u8, "");
                },
                .ctrl_d => {
                    if (buf.len() == 0) {
                        try w.writeAll(EOL);
                        try w.flush();
                        return null;
                    }
                    buf.deleteForward();
                },
                .up => if (self.history.up()) |entry| {
                    try buf.set(entry);
                },
                .down => {
                    if (self.history.down()) |entry| {
                        try buf.set(entry);
                    } else {
                        buf.clear();
                    }
                },
                .tab => {}, // TODO: implement the compleation
                .unknown => {},
            }

            try renderLine(w, self.prompt, buf.items(), buf.cursor);
            try w.flush();
        }

        try w.writeAll(EOL);
        try w.flush();
        return try buf.toOwnedSlice();
    }

    pub fn readLineCooked(self: *Self, w: *Io.Writer, r: *Io.Reader) Error!?[]u8 {
        try w.writeAll(self.prompt);
        try w.flush();

        var line: std.ArrayList(u8) = .empty;
        defer line.deinit(self.gpa);

        var saw_any = false;
        while (true) {
            const b = r.takeByte() catch |e| switch (e) {
                error.EndOfStream => {
                    if (!saw_any) {
                        return null;
                    }
                    break;
                },
                else => return e,
            };
            saw_any = true;
            if (b == '\n') {
                break;
            }
            if (b == '\r') {
                continue;
            }
            try line.append(self.gpa, b);
        }
        return try line.toOwnedSlice(self.gpa);
    }
};
