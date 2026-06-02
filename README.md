# zigline

A small line-editing dependency-free library for Zig.
Cousin of [readline](https://en.wikipedia.org/wiki/GNU_Readline)/[replxx](https://github.com/AmokHuginnsson/replxx).

## What is here:

- **An editable input line:** left/right arrows, Home/End, Backspace/Delete,
  and the usual shortcuts: Ctrl-A (start), Ctrl-E (end), Ctrl-U / Ctrl-K
  (delete to start / end), Ctrl-L (clear screen), Ctrl-C (cancel the line),
  Ctrl-D (quit on an empty line).
- **History:** kept in memory for the session; walk through it with Up/Down.
- **A small command parser:** splits a line into pieces the way a shell does,
  so `git commit -m "a message"` becomes
  `["git", "commit", "-m", "a message"]`. It understands quotes and backslash
  escapes.
- **Basic UTF-8:** accented letters, Cyrillic, Greek, emoji, etc. are treated
  as single characters when you move or delete (not chopped in half).

## A quick example (main.zig)

```zig
const std = @import("std");
const Io = std.Io;

const zigline = @import("zigline");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const out = &stdout_file_writer.interface;

    try out.writeAll("zigline demo REPL\n\n");
    try out.flush();

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

        try out.print("{d} token(s):\n", .{tokens.len});
        for (tokens, 0..) |tok, i| {
            try out.print("  [{d}] '{s}'\n", .{ i, tok });
        }
        try out.flush();

        try editor.historyAdd(line);
    }

    try out.writeAll("noniin!\n");
    try out.flush();
}
```

That's basically the included demo. You can see the full version in
[`src/main.zig`](src/main.zig).

## Output example:

```
zigline> Helo, world
2 token(s):
  [0] 'Helo,'
  [1] 'world'
zigline> päivää, mitä kuuluu
3 token(s):
  [0] 'päivää,'
  [1] 'mitä'
  [2] 'kuuluu'
zigline> تسجّل الآن لحضور المؤتمر الدولي العاشر ليونيكود (Unicode Conference)
9 token(s):
  [0] 'تسجّل'
  [1] 'الآن'
  [2] 'لحضور'
  [3] 'المؤتمر'
  [4] 'الدولي'
  [5] 'العاشر'
  [6] 'ليونيكود'
  [7] '(Unicode'
  [8] 'Conference)'
zigline> line with a "double ' quotes" and 'single " quotes'
6 token(s):
  [0] 'line'
  [1] 'with'
  [2] 'a'
  [3] 'double ' quotes'
  [4] 'and'
  [5] 'single " quotes'
```

## Requires

    Zig 0.16

## What it doesn't (yet) do

This is intentionally small. There's no tab-completion, no syntax highlighting,
no reverse search (Ctrl-R), no multi-line editing, and no saving history to a
file. Wide characters (like CJK or emoji that take two columns) are handled as
single units but may nudge the cursor by a column. These are all things that
could be added later.

## License

MIT
