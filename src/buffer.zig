const std = @import("std");
const Allocator = std.mem.Allocator;

fn prevBoundary(items: []const u8, idx: usize) usize {
    var i = idx - 1;
    while ((i > 0) and ((items[i] & 0xC0) == 0x80)) {
        i -= 1;
    }
    return i;
}

fn seqLen(lead: u8) usize {
    return std.unicode.utf8ByteSequenceLength(lead) catch 1;
}

pub const Buffer = struct {
    const Self = @This();

    pub const Error = Allocator.Error;

    gpa: Allocator,
    bytes: std.ArrayList(u8),
    cursor: usize,

    pub fn init(gpa: Allocator) Buffer {
        return .{
            .gpa = gpa,
            .bytes = .empty,
            .cursor = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.bytes.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn items(self: *const Self) []const u8 {
        return self.bytes.items;
    }

    pub fn len(self: *const Self) usize {
        return self.bytes.items.len;
    }

    pub fn insertByte(self: *Self, c: u8) Error!void {
        try self.bytes.insert(self.gpa, self.cursor, c);
        self.cursor += 1;
    }

    pub fn insertSlice(self: *Self, s: []const u8) Error!void {
        try self.bytes.insertSlice(self.gpa, self.cursor, s);
        self.cursor += s.len;
    }

    /// Backspace
    pub fn backspace(self: *Self) void {
        if (self.cursor == 0) {
            return;
        }
        const start = prevBoundary(self.bytes.items, self.cursor);
        self.bytes.replaceRangeAssumeCapacity(start, self.cursor - start, &.{});
        self.cursor = start;
    }

    /// Del
    pub fn deleteForward(self: *Self) void {
        const data = self.bytes.items;
        if (self.cursor >= data.len) {
            return;
        }
        const n = @min(seqLen(data[self.cursor]), data.len - self.cursor);
        self.bytes.replaceRangeAssumeCapacity(self.cursor, n, &.{});
    }

    pub fn moveLeft(self: *Self) void {
        if (self.cursor > 0) {
            self.cursor = prevBoundary(self.bytes.items, self.cursor);
        }
    }

    pub fn moveRight(self: *Self) void {
        const data = self.bytes.items;
        if (self.cursor < data.len) {
            self.cursor = @min(self.cursor + seqLen(data[self.cursor]), data.len);
        }
    }

    pub fn moveHome(self: *Self) void {
        self.cursor = 0;
    }

    pub fn moveEnd(self: *Self) void {
        self.cursor = self.bytes.items.len;
    }

    pub fn deleteToEnd(self: *Self) void {
        self.bytes.shrinkRetainingCapacity(self.cursor);
    }

    pub fn deleteToStart(self: *Self) void {
        self.bytes.replaceRangeAssumeCapacity(0, self.cursor, &.{});
        self.cursor = 0;
    }

    pub fn set(self: *Self, s: []const u8) Error!void {
        self.bytes.clearRetainingCapacity();
        try self.bytes.appendSlice(self.gpa, s);
        self.cursor = self.bytes.items.len;
    }

    pub fn clear(self: *Self) void {
        self.bytes.clearRetainingCapacity();
        self.cursor = 0;
    }

    pub fn toOwnedSlice(self: *Self) Error![]u8 {
        return self.gpa.dupe(u8, self.bytes.items);
    }
};
