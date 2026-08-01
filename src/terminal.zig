//!
//! terminal.zig - Terminal handling for line editing
//!
//! @author
//!     newenclave
//! @license
//!     MIT
//! @see
//!     github.com/newenclave/zigline
//!
const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const Codepoint = u21;

pub const Key = union(enum) {
    codepoint: Codepoint,
    enter,
    backspace,
    delete,
    tab,
    left,
    right,
    up,
    down,
    home,
    end,
    ctrl_a,
    ctrl_e,
    ctrl_u,
    ctrl_k,
    ctrl_l,
    ctrl_c,
    ctrl_d,
    unknown,
};

pub const ReadError = std.Io.Reader.Error;

pub fn readKey(r: *std.Io.Reader) ReadError!Key {
    const b = try r.takeByte();
    return switch (b) {
        '\r' => .enter,
        '\n' => .enter,
        '\t' => .tab,
        0x1b => readEscape(r),
        0x7f => .backspace,
        0x08 => .backspace,
        0x01 => .ctrl_a,
        0x03 => .ctrl_c,
        0x04 => .ctrl_d,
        0x05 => .ctrl_e,
        0x0b => .ctrl_k,
        0x0c => .ctrl_l,
        0x15 => .ctrl_u,
        else => decodeText(r, b),
    };
}

fn decodeText(r: *std.Io.Reader, lead: u8) Key {
    if (lead < 0x20) {
        return .unknown;
    }
    if (lead < 0x80) {
        return .{
            .codepoint = lead,
        };
    }
    const len = std.unicode.utf8ByteSequenceLength(lead) catch {
        return .unknown;
    };
    var bytes: [4]u8 = undefined;
    bytes[0] = lead;
    var i: usize = 1;
    while (i < len) : (i += 1) {
        bytes[i] = nextByte(r) orelse {
            return .unknown;
        };
    }
    const cp = std.unicode.utf8Decode(bytes[0..len]) catch {
        return .unknown;
    };
    return .{ .codepoint = cp };
}

fn nextByte(r: *std.Io.Reader) ?u8 {
    return r.takeByte() catch null;
}

fn readEscape(r: *std.Io.Reader) Key {
    return switch (nextByte(r) orelse return .unknown) {
        '[' => readCsi(r),
        'O' => readSs3(r), // SS3, arrows/Home/End
        else => .unknown,
    };
}

fn readCsi(r: *std.Io.Reader) Key {
    // CSI sequence: ESC [ <params> <intermediates> <final>
    var num: u16 = 0;
    var have_num = false;
    var seen_semicolon = false;
    const final = while (true) {
        const b = nextByte(r) orelse {
            return .unknown;
        };
        switch (b) {
            '0'...'9' => if (!seen_semicolon) {
                num = num *| 10 +| (b - '0');
                have_num = true;
            },
            ';' => seen_semicolon = true,
            0x3a => {},
            0x3c...0x3f => {},
            0x20...0x2f => {},
            0x40...0x7e => break b,
            else => return .unknown,
        }
    };
    return switch (final) {
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        '~' => if (have_num) switch (num) {
            1, 7 => .home,
            3 => .delete,
            4, 8 => .end,
            else => .unknown,
        } else .unknown,
        else => .unknown,
    };
}

fn readSs3(r: *std.Io.Reader) Key {
    // Single Shifts 3 (SS3) sequence: ESC O <final>
    return switch (nextByte(r) orelse return .unknown) {
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        else => .unknown,
    };
}

pub const Geometry = switch (native_os) {
    .windows => WindowsGeometry,
    else => PosixGeometry,
};

const GeometryCoord = struct {
    x: u16,
    y: u16,
};

const PosixGeometry = struct {
    pub const Coord = GeometryCoord;
    pub const GeometryError = error{ NotATerminal, OutputFailed };
    pub const Error = GeometryError;

    const ioctl_get_winsize: c_int = switch (native_os) {
        .linux => @intCast(std.os.linux.T.IOCGWINSZ),
        .macos, .freebsd, .netbsd, .openbsd => @bitCast(@as(u32, 0x40087468)),
        else => @compileError("terminal.Geometry is unsupported on this platform"),
    };
    const ioctl_set_winsize: c_int = switch (native_os) {
        .linux => @intCast(std.os.linux.T.IOCSWINSZ),
        .macos, .freebsd, .netbsd, .openbsd => @bitCast(@as(u32, 0x80087467)),
        else => @compileError("terminal.Geometry is unsupported on this platform"),
    };

    fn writeAll(bytes: []const u8) GeometryError!void {
        var remaining = bytes;
        while (remaining.len > 0) {
            const written = std.c.write(std.Io.File.stdout().handle, remaining.ptr, remaining.len);
            if (written <= 0) return error.OutputFailed;
            remaining = remaining[@intCast(written)..];
        }
    }

    pub fn size() GeometryError!Coord {
        var window_size: std.posix.winsize = undefined;
        const result = std.c.ioctl(
            std.Io.File.stdout().handle,
            ioctl_get_winsize,
            @intFromPtr(&window_size),
        );
        if (std.posix.errno(result) != .SUCCESS) return error.NotATerminal;
        return .{ .x = window_size.col, .y = window_size.row };
    }

    pub fn clear() GeometryError!void {
        const window_size = try size();
        const spaces = [_]u8{' '} ** 256;
        var row: u16 = 0;
        while (row < window_size.y) : (row += 1) {
            try setPos(0, row);
            var remaining = window_size.x;
            while (remaining > 0) {
                const len = @min(remaining, spaces.len);
                try writeAll(spaces[0..len]);
                remaining -= @intCast(len);
            }
        }
    }

    pub fn setPos(x: u16, y: u16) GeometryError!void {
        var buffer: [24]u8 = undefined;
        const sequence = std.fmt.bufPrint(&buffer, "\x1b[{d};{d}H", .{
            @as(u32, y) + 1,
            @as(u32, x) + 1,
        }) catch return error.OutputFailed;
        try writeAll(sequence);
    }

    pub fn setSize(x: u16, y: u16) GeometryError!void {
        var window_size = std.posix.winsize{ .row = y, .col = x, .xpixel = 0, .ypixel = 0 };
        const result = std.c.ioctl(
            std.Io.File.stdout().handle,
            ioctl_set_winsize,
            @intFromPtr(&window_size),
        );
        if (std.posix.errno(result) != .SUCCESS) return error.NotATerminal;
    }

    pub fn hideCursor() GeometryError!void {
        try writeAll("\x1b[?25l");
    }

    pub fn showCursor() GeometryError!void {
        try writeAll("\x1b[?25h");
    }
};

const WindowsGeometry = struct {
    const w = std.os.windows;

    const CoordWin = extern struct { X: w.SHORT, Y: w.SHORT };
    const SmallRect = extern struct { Left: w.SHORT, Top: w.SHORT, Right: w.SHORT, Bottom: w.SHORT };
    const ConsoleScreenBufferInfo = extern struct {
        dwSize: CoordWin,
        dwCursorPosition: CoordWin,
        wAttributes: w.WORD,
        srWindow: SmallRect,
        dwMaximumWindowSize: CoordWin,
    };
    const ConsoleCursorInfo = extern struct {
        dwSize: w.DWORD,
        bVisible: w.BOOL,
    };

    extern "kernel32" fn GetConsoleScreenBufferInfo(
        handle: w.HANDLE,
        info: *ConsoleScreenBufferInfo,
    ) callconv(.winapi) w.BOOL;
    extern "kernel32" fn FillConsoleOutputCharacterA(
        handle: w.HANDLE,
        character: u8,
        length: w.DWORD,
        position: CoordWin,
        written: *w.DWORD,
    ) callconv(.winapi) w.BOOL;
    extern "kernel32" fn SetConsoleCursorPosition(
        handle: w.HANDLE,
        position: CoordWin,
    ) callconv(.winapi) w.BOOL;
    extern "kernel32" fn GetConsoleCursorInfo(
        handle: w.HANDLE,
        info: *ConsoleCursorInfo,
    ) callconv(.winapi) w.BOOL;
    extern "kernel32" fn SetConsoleCursorInfo(
        handle: w.HANDLE,
        info: *const ConsoleCursorInfo,
    ) callconv(.winapi) w.BOOL;

    pub const Coord = GeometryCoord;
    pub const GeometryError = error{ NotATerminal, OperationFailed, InvalidCoordinate };
    pub const Error = GeometryError;

    fn boolSucceeded(value: w.BOOL) bool {
        return switch (@typeInfo(w.BOOL)) {
            .int => value != 0,
            .@"enum" => @intFromEnum(value) != 0,
            else => @compileError("unexpected Windows BOOL representation"),
        };
    }

    fn boolFrom(value: bool) w.BOOL {
        return switch (@typeInfo(w.BOOL)) {
            .int => @intFromBool(value),
            .@"enum" => @enumFromInt(@intFromBool(value)),
            else => @compileError("unexpected Windows BOOL representation"),
        };
    }

    fn screenBufferInfo() GeometryError!ConsoleScreenBufferInfo {
        var info: ConsoleScreenBufferInfo = undefined;
        if (!boolSucceeded(GetConsoleScreenBufferInfo(std.Io.File.stdout().handle, &info))) {
            return error.NotATerminal;
        }
        return info;
    }

    fn toCoord(x: u16, y: u16) GeometryError!CoordWin {
        if (x > std.math.maxInt(w.SHORT) or y > std.math.maxInt(w.SHORT)) {
            return error.InvalidCoordinate;
        }
        return .{ .X = @intCast(x), .Y = @intCast(y) };
    }

    pub fn size() GeometryError!Coord {
        const info = try screenBufferInfo();
        return .{
            .x = @intCast(info.srWindow.Right - info.srWindow.Left + 1),
            .y = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1),
        };
    }

    pub fn clear() GeometryError!void {
        const handle = std.Io.File.stdout().handle;
        const info = try screenBufferInfo();
        if (info.dwSize.X < 0 or info.dwSize.Y < 0) return error.OperationFailed;
        const length: w.DWORD = @intCast(@as(u32, @intCast(info.dwSize.X)) * @as(u32, @intCast(info.dwSize.Y)));
        var written: w.DWORD = 0;
        if (!boolSucceeded(FillConsoleOutputCharacterA(
            handle,
            ' ',
            length,
            .{ .X = 0, .Y = 0 },
            &written,
        ))) {
            return error.OperationFailed;
        }
        if (written != length) return error.OperationFailed;
        try setPos(0, 0);
    }

    pub fn setPos(x: u16, y: u16) GeometryError!void {
        if (!boolSucceeded(SetConsoleCursorPosition(
            std.Io.File.stdout().handle,
            try toCoord(x, y),
        ))) {
            return error.OperationFailed;
        }
    }

    fn setCursorVisible(visible: bool) GeometryError!void {
        var info: ConsoleCursorInfo = undefined;
        const handle = std.Io.File.stdout().handle;
        if (!boolSucceeded(GetConsoleCursorInfo(handle, &info))) return error.NotATerminal;
        info.bVisible = boolFrom(visible);
        if (!boolSucceeded(SetConsoleCursorInfo(handle, &info))) return error.OperationFailed;
    }

    pub fn hideCursor() GeometryError!void {
        try setCursorVisible(false);
    }

    pub fn showCursor() GeometryError!void {
        try setCursorVisible(true);
    }
};

pub const Color = enum {
    none,
    red,
    green,
    blue,
    yellow,
    white,
    cyan,
};

pub const ColorOutput = switch (native_os) {
    .windows => WindowsColorOutput,
    else => PosixColorOutput,
};

pub const ColorError = ColorOutput.Error;

pub fn setColor(color: Color) ColorError!void {
    try ColorOutput.set(color);
}

pub fn light() ColorError!void {
    try setColor(.white);
}

pub fn red() ColorError!void {
    try setColor(.red);
}

pub fn green() ColorError!void {
    try setColor(.green);
}

pub fn blue() ColorError!void {
    try setColor(.blue);
}

pub fn yellow() ColorError!void {
    try setColor(.yellow);
}

pub fn none() ColorError!void {
    try setColor(.none);
}

pub fn cyan() ColorError!void {
    try setColor(.cyan);
}

const PosixColorOutput = struct {
    pub const OutputError = error{OutputFailed};
    pub const Error = OutputError;

    pub fn set(color: Color) OutputError!void {
        const sequence = switch (color) {
            .none => "\x1b[0m",
            .red => "\x1b[31;1m",
            .green => "\x1b[32;1m",
            .blue => "\x1b[34;1m",
            .yellow => "\x1b[33;1m",
            .white => "\x1b[37;1m",
            .cyan => "\x1b[36;1m",
        };

        var remaining = sequence;
        while (remaining.len > 0) {
            const written = std.c.write(std.Io.File.stdout().handle, remaining.ptr, remaining.len);
            if (written <= 0) return error.OutputFailed;
            remaining = remaining[@intCast(written)..];
        }
    }
};

const WindowsColorOutput = struct {
    const w = std.os.windows;

    extern "kernel32" fn SetConsoleTextAttribute(handle: w.HANDLE, attributes: w.WORD) callconv(.winapi) w.BOOL;

    pub const OutputError = error{SetColorFailed};
    pub const Error = OutputError;

    fn boolSucceeded(value: w.BOOL) bool {
        return switch (@typeInfo(w.BOOL)) {
            .int => value != 0,
            .@"enum" => @intFromEnum(value) != 0,
            else => @compileError("unexpected Windows BOOL representation"),
        };
    }

    pub fn set(color: Color) OutputError!void {
        const attributes: w.WORD = switch (color) {
            .none => 0x0008,
            .red => 0x000c,
            .green => 0x000a,
            .blue => 0x0009,
            .yellow => 0x000e,
            .white => 0x000f,
            .cyan => 0x000b,
        };
        if (!boolSucceeded(SetConsoleTextAttribute(std.Io.File.stdout().handle, attributes))) {
            return error.SetColorFailed;
        }
    }
};

pub const RawMode = switch (native_os) {
    .windows => WindowsRawMode,
    else => PosixRawMode,
};

pub const Error = RawMode.ErrorSet;

const PosixRawMode = struct {
    pub const ErrorSet = std.posix.TermiosGetError ||
        std.posix.TermiosSetError ||
        std.posix.TIOCError;

    fd: std.posix.fd_t,
    original: std.posix.termios,

    pub fn enable() ErrorSet!PosixRawMode {
        const fd = std.Io.File.stdin().handle;
        const original = try std.posix.tcgetattr(fd);
        var raw = original;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        raw.iflag.ICRNL = false;
        raw.iflag.IXON = false;
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;

        raw.oflag.OPOST = false;

        raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

        try std.posix.tcsetattr(fd, .DRAIN, raw);
        return .{
            .fd = fd,
            .original = original,
        };
    }

    pub fn disable(self: *PosixRawMode) void {
        std.posix.tcsetattr(self.fd, .DRAIN, self.original) catch {};
    }
};

const WindowsRawMode = struct {
    const w = std.os.windows;

    const ENABLE_PROCESSED_INPUT: w.DWORD = 0x0001;
    const ENABLE_LINE_INPUT: w.DWORD = 0x0002;
    const ENABLE_ECHO_INPUT: w.DWORD = 0x0004;
    const ENABLE_VIRTUAL_TERMINAL_INPUT: w.DWORD = 0x0200;

    const ENABLE_PROCESSED_OUTPUT: w.DWORD = 0x0001;
    const ENABLE_VIRTUAL_TERMINAL_PROCESSING: w.DWORD = 0x0004;

    const cp_utf8: c_uint = 65001;

    extern "kernel32" fn GetConsoleCP() callconv(.winapi) w.UINT;
    extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) w.UINT;

    extern "kernel32" fn SetConsoleCP(cp: w.UINT) callconv(.winapi) w.BOOL;
    extern "kernel32" fn SetConsoleOutputCP(cp: w.UINT) callconv(.winapi) w.BOOL;

    extern "kernel32" fn GetConsoleMode(hConsoleHandle: w.HANDLE, lpMode: *w.DWORD) callconv(.winapi) w.BOOL;
    extern "kernel32" fn SetConsoleMode(hConsoleHandle: w.HANDLE, dwMode: w.DWORD) callconv(.winapi) w.BOOL;

    pub const ErrorSet = error{ NotATerminal, SetConsoleModeFailed };

    fn boolSucceeded(value: w.BOOL) bool {
        return switch (@typeInfo(w.BOOL)) {
            .int => value != 0,
            .@"enum" => @intFromEnum(value) != 0,
            else => @compileError("unexpected Windows BOOL representation"),
        };
    }

    in_handle: w.HANDLE,
    out_handle: w.HANDLE,
    in_original: w.DWORD,
    out_original: w.DWORD,
    cp_original: w.UINT,
    cp_output_original: w.UINT,

    pub fn enable() ErrorSet!WindowsRawMode {
        const in_handle = std.Io.File.stdin().handle;
        const out_handle = std.Io.File.stdout().handle;

        var in_mode: w.DWORD = 0;
        var out_mode: w.DWORD = 0;

        const cp_original = GetConsoleCP();
        const cp_output_original = GetConsoleOutputCP();

        _ = SetConsoleCP(cp_utf8);
        _ = SetConsoleOutputCP(cp_utf8);

        if (!boolSucceeded(GetConsoleMode(in_handle, &in_mode))) {
            return ErrorSet.NotATerminal;
        }
        if (!boolSucceeded(GetConsoleMode(out_handle, &out_mode))) {
            return ErrorSet.NotATerminal;
        }

        var new_in = in_mode;
        new_in &= ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT);
        new_in |= ENABLE_VIRTUAL_TERMINAL_INPUT;

        var new_out = out_mode;
        new_out |= ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING;

        if (!boolSucceeded(SetConsoleMode(in_handle, new_in))) {
            return ErrorSet.SetConsoleModeFailed;
        }
        if (!boolSucceeded(SetConsoleMode(out_handle, new_out))) {
            _ = SetConsoleMode(in_handle, in_mode);
            return ErrorSet.SetConsoleModeFailed;
        }

        return .{
            .in_handle = in_handle,
            .out_handle = out_handle,
            .in_original = in_mode,
            .out_original = out_mode,
            .cp_original = cp_original,
            .cp_output_original = cp_output_original,
        };
    }

    pub fn disable(self: *WindowsRawMode) void {
        _ = SetConsoleMode(self.in_handle, self.in_original);
        _ = SetConsoleMode(self.out_handle, self.out_original);
        _ = SetConsoleCP(self.cp_original);
        _ = SetConsoleOutputCP(self.cp_output_original);
    }
};
