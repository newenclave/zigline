//!
//! history.zig - History for line editing
//!
//! @author
//!     newenclave
//! @license
//!     MIT
//! @see
//!     github.com/newenclave/zigline
//!
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const History = struct {
    const Self = @This();

    pub const Error = Allocator.Error;

    gpa: Allocator,
    entries: std.ArrayList([]u8),
    max: usize,
    pos: usize,

    pub fn init(gpa: Allocator, max: usize) Self {
        return .{
            .gpa = gpa,
            .entries = .empty,
            .max = @max(max, 1),
            .pos = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries.items) |e| {
            self.gpa.free(e);
        }
        self.entries.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn count(self: *const Self) usize {
        return self.entries.items.len;
    }

    pub fn get(self: *const Self, idx: usize) []const u8 {
        return self.entries.items[idx];
    }

    pub fn add(self: *Self, line: []const u8) Error!void {
        defer self.resetNav();
        if (line.len == 0) {
            return;
        }
        if ((self.entries.items.len > 0) and
            std.mem.eql(u8, self.entries.items[self.entries.items.len - 1], line))
        {
            return;
        }

        const owned = try self.gpa.dupe(u8, line);
        errdefer self.gpa.free(owned);

        try self.entries.append(self.gpa, owned);

        if (self.entries.items.len > self.max) {
            const oldest = self.entries.orderedRemove(0);
            self.gpa.free(oldest);
        }
    }

    pub fn resetNav(self: *Self) void {
        self.pos = self.entries.items.len;
    }

    pub fn up(self: *Self) ?[]const u8 {
        if (self.entries.items.len == 0) {
            return null;
        }
        if (self.pos > 0) {
            self.pos -= 1;
        }
        return self.entries.items[self.pos];
    }

    pub fn down(self: *Self) ?[]const u8 {
        if (self.pos >= self.entries.items.len) {
            return null;
        }
        self.pos += 1;
        if (self.pos == self.entries.items.len) {
            return null;
        }
        return self.entries.items[self.pos];
    }
};
