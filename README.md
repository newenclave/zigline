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
- **Braille scenes:** static or dynamically allocated 2x4-dot canvases that
  can be rendered at any terminal position.
- **Console control:** raw input mode, key decoding, terminal geometry, cursor
  visibility, screen clearing, and a small color palette on POSIX and Windows.

## Braille scenes

Scene dimensions and drawing coordinates are specified in Braille dots. One
terminal character represents a `2 x 4` group of dots. `renderAt` takes
terminal-column and terminal-row coordinates; it clips anything outside the
visible terminal area.

```zig
const Scene = zigline.braille.StaticScene(16, 12);
var scene: Scene = .{};
_ = scene.setDot(0, 0);
_ = scene.setDot(15, 11);
try scene.renderAt(out, 4, 2);
try out.flush();
```

Use `DynamicScene` when the dimensions are available only at runtime:

```zig
var scene = try zigline.braille.DynamicScene.init(gpa, width, height);
defer scene.deinit();

_ = scene.setDot(0, 0);
try scene.renderAt(out, 4, 2);
try out.flush();
```

`renderWithAt` lets a renderer react to every visible Braille glyph. It calls
`beginRender` once, `beforeCell` before each glyph, and `endRender` after the
last glyph. The renderer can keep state in its mutable context and write any
terminal control sequences through the supplied writer; the scene always writes
the glyph itself.

## Console control

`zigline.terminal` provides the low-level terminal operations used by the line
editor. `RawMode.enable` switches stdin to byte-by-byte input and restores the
previous console state with `disable`. `readKey` decodes UTF-8 text, common
control keys, and CSI/SS3 escape sequences such as arrows, Home, End, and
Delete.

`Geometry` exposes the current size plus `clear`, `setPos`, `hideCursor`, and
`showCursor`. The `red`, `green`, `blue`, `yellow`, `cyan`, `light`, and `none`
helpers change stdout color.

```zig
const terminal = zigline.terminal;

var raw = try terminal.RawMode.enable();
defer raw.disable();

const size = try terminal.Geometry.size();
try terminal.Geometry.setPos(0, size.y - 1);
try terminal.green();
defer terminal.none() catch {};
```

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
