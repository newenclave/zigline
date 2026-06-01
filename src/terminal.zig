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

pub const RawMode = switch (native_os) {
    .windows => WindowsRawMode,
    else => PosixRawMode,
};

const PosixRawMode = struct {
    const Error = std.posix.TermiosGetError || std.posix.TIOCError;

    fd: std.posix.fd_t,
    original: std.posix.termios,

    pub fn enable() Error!PosixRawMode {
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

    extern "kernel32" fn GetConsoleMode(hConsoleHandle: w.HANDLE, lpMode: *w.DWORD) callconv(.winapi) w.BOOL;
    extern "kernel32" fn SetConsoleMode(hConsoleHandle: w.HANDLE, dwMode: w.DWORD) callconv(.winapi) w.BOOL;

    const Error = error{ NotATerminal, SetConsoleModeFailed };

    in_handle: w.HANDLE,
    out_handle: w.HANDLE,
    in_original: w.DWORD,
    out_original: w.DWORD,

    pub fn enable() Error!WindowsRawMode {
        const in_handle = std.Io.File.stdin().handle;
        const out_handle = std.Io.File.stdout().handle;

        var in_mode: w.DWORD = 0;
        var out_mode: w.DWORD = 0;
        if (!GetConsoleMode(in_handle, &in_mode).toBool()) {
            return Error.NotATerminal;
        }
        if (!GetConsoleMode(out_handle, &out_mode).toBool()) {
            return Error.NotATerminal;
        }

        var new_in = in_mode;
        new_in &= ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT);
        new_in |= ENABLE_VIRTUAL_TERMINAL_INPUT;

        var new_out = out_mode;
        new_out |= ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING;

        if (!SetConsoleMode(in_handle, new_in).toBool()) {
            return Error.SetConsoleModeFailed;
        }
        if (!SetConsoleMode(out_handle, new_out).toBool()) {
            _ = SetConsoleMode(in_handle, in_mode);
            return Error.SetConsoleModeFailed;
        }

        return .{
            .in_handle = in_handle,
            .out_handle = out_handle,
            .in_original = in_mode,
            .out_original = out_mode,
        };
    }

    pub fn disable(self: *WindowsRawMode) void {
        _ = SetConsoleMode(self.in_handle, self.in_original);
        _ = SetConsoleMode(self.out_handle, self.out_original);
    }
};
