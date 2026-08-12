const std = @import("std");
const terminal = @import("terminal.zig");

const MIN: u8 = 0x00;
const BASE: u32 = 0x2800;
const DOTS = [_]u8{ 0x01, 0x02, 0x04, 0x40, 0x08, 0x10, 0x20, 0x80 };

pub fn empty() u8 {
    return MIN;
}

pub fn setDot(src: u8, x: usize, y: usize) u8 {
    const id = x * 4 + y;
    if (id < DOTS.len) {
        return src | DOTS[id];
    } else {
        return src;
    }
}

pub fn cleanDot(src: u8, x: usize, y: usize) u8 {
    const id = x * 4 + y;
    if (id < DOTS.len) {
        return src & ~DOTS[id];
    } else {
        return src;
    }
}

const applySetDot = setDot;
const applyCleanDot = cleanDot;

pub const RenderError = terminal.Geometry.Error || std.Io.Writer.Error;

pub fn toUnicode(src: u8) u32 {
    return BASE + src;
}

fn cellWidth(width: usize) usize {
    return width / 2 + @intFromBool(width % 2 != 0);
}

fn cellHeight(height: usize) usize {
    return height / 4 + @intFromBool(height % 4 != 0);
}

fn changeDot(
    cells: []u8,
    width: usize,
    height: usize,
    cells_per_row: usize,
    x: usize,
    y: usize,
    comptime change: fn (u8, usize, usize) u8,
) bool {
    if (x >= width or y >= height) {
        return false;
    }

    const index = (y / 4) * cells_per_row + x / 2;
    cells[index] = change(cells[index], x % 2, y % 4);
    return true;
}

fn renderCells(
    writer: *std.Io.Writer,
    cells: []const u8,
    width_in_cells: usize,
    height_in_cells: usize,
    x: u16,
    y: u16,
) RenderError!void {
    const terminal_size = try terminal.Geometry.size();
    if (x >= terminal_size.x or y >= terminal_size.y) {
        return;
    }

    const visible_width: usize = @min(width_in_cells, @as(usize, terminal_size.x - x));
    const visible_height: usize = @min(height_in_cells, @as(usize, terminal_size.y - y));

    // Geometry moves the console cursor outside the buffered writer.
    try writer.flush();
    for (0..visible_height) |row| {
        try terminal.Geometry.setPos(x, y + @as(u16, @intCast(row)));
        for (0..visible_width) |column| {
            var utf8: [4]u8 = undefined;
            const cell = cells[row * width_in_cells + column];
            const len = std.unicode.utf8Encode(@intCast(toUnicode(cell)), &utf8) catch unreachable;
            try writer.writeAll(utf8[0..len]);
        }
        try writer.flush();
    }
}

fn renderWithCells(
    writer: *std.Io.Writer,
    cells: []const u8,
    width_in_cells: usize,
    height_in_cells: usize,
    x: u16,
    y: u16,
    context: anytype,
    comptime Renderer: type,
) (RenderError || Renderer.Error)!void {
    const terminal_size = try terminal.Geometry.size();
    if (x >= terminal_size.x or y >= terminal_size.y) {
        return;
    }

    const visible_width: usize = @min(width_in_cells, @as(usize, terminal_size.x - x));
    const visible_height: usize = @min(height_in_cells, @as(usize, terminal_size.y - y));
    if (visible_width == 0 or visible_height == 0) {
        return;
    }

    // Geometry moves the console cursor outside the buffered writer.
    try writer.flush();
    try Renderer.beginRender(context, writer);
    var render_finished = false;
    errdefer if (!render_finished) {
        Renderer.endRender(context, writer) catch {};
    };

    for (0..visible_height) |row| {
        try terminal.Geometry.setPos(x, y + @as(u16, @intCast(row)));
        try renderVisibleRow(writer, cells, row, width_in_cells, visible_width, context, Renderer);
        try writer.flush();
    }
    render_finished = true;
    try Renderer.endRender(context, writer);
    try writer.flush();
}

fn renderVisibleRow(
    writer: *std.Io.Writer,
    cells: []const u8,
    row: usize,
    width_in_cells: usize,
    visible_width: usize,
    context: anytype,
    comptime Renderer: type,
) (std.Io.Writer.Error || Renderer.Error)!void {
    for (0..visible_width) |column| {
        var utf8: [4]u8 = undefined;
        const cell = cells[row * width_in_cells + column];
        const len = std.unicode.utf8Encode(@intCast(toUnicode(cell)), &utf8) catch unreachable;
        const glyph = utf8[0..len];
        try Renderer.beforeCell(context, writer, column, row, glyph);
        try writer.writeAll(glyph);
    }
}

pub fn StaticScene(comptime width: usize, comptime height: usize) type {
    const scene_cell_width = cellWidth(width);
    const scene_cell_height = cellHeight(height);
    const cell_count = scene_cell_width * scene_cell_height;

    return struct {
        pub const dot_width = width;
        pub const dot_height = height;
        pub const width_in_cells = scene_cell_width;
        pub const height_in_cells = scene_cell_height;

        cells: [cell_count]u8 = [_]u8{MIN} ** cell_count,

        const Self = @This();

        pub fn setDot(self: *Self, x: usize, y: usize) bool {
            return changeDot(
                &self.cells,
                width,
                height,
                scene_cell_width,
                x,
                y,
                applySetDot,
            );
        }

        pub fn cleanDot(self: *Self, x: usize, y: usize) bool {
            return changeDot(
                &self.cells,
                width,
                height,
                scene_cell_width,
                x,
                y,
                applyCleanDot,
            );
        }

        pub fn clean(self: *Self) void {
            @memset(self.cells[0..], MIN);
        }

        pub fn cellAt(self: *const Self, x: usize, y: usize) ?u8 {
            if (x >= scene_cell_width or y >= scene_cell_height) {
                return null;
            }
            return self.cells[y * scene_cell_width + x];
        }

        pub fn renderAt(self: *const Self, writer: *std.Io.Writer, x: u16, y: u16) RenderError!void {
            try renderCells(
                writer,
                &self.cells,
                scene_cell_width,
                scene_cell_height,
                x,
                y,
            );
        }

        pub fn renderWithAt(
            self: *const Self,
            writer: *std.Io.Writer,
            x: u16,
            y: u16,
            context: anytype,
            comptime Renderer: type,
        ) (RenderError || Renderer.Error)!void {
            try renderWithCells(
                writer,
                &self.cells,
                scene_cell_width,
                scene_cell_height,
                x,
                y,
                context,
                Renderer,
            );
        }
    };
}

pub const DynamicScene = struct {
    allocator: std.mem.Allocator,
    dot_width: usize,
    dot_height: usize,
    width_in_cells: usize,
    height_in_cells: usize,
    cells: []u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) (error{Overflow} || std.mem.Allocator.Error)!Self {
        const width_in_cells = cellWidth(width);
        const height_in_cells = cellHeight(height);
        const count = std.math.mul(usize, width_in_cells, height_in_cells) catch return error.Overflow;
        const cells = try allocator.alloc(u8, count);
        @memset(cells, MIN);

        return .{
            .allocator = allocator,
            .dot_width = width,
            .dot_height = height,
            .width_in_cells = width_in_cells,
            .height_in_cells = height_in_cells,
            .cells = cells,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.cells);
        self.cells = &.{};
    }

    pub fn setDot(self: *Self, x: usize, y: usize) bool {
        return changeDot(
            self.cells,
            self.dot_width,
            self.dot_height,
            self.width_in_cells,
            x,
            y,
            applySetDot,
        );
    }

    pub fn cleanDot(self: *Self, x: usize, y: usize) bool {
        return changeDot(
            self.cells,
            self.dot_width,
            self.dot_height,
            self.width_in_cells,
            x,
            y,
            applyCleanDot,
        );
    }

    pub fn clean(self: *Self) void {
        @memset(self.cells, MIN);
    }

    pub fn cellAt(self: *const Self, x: usize, y: usize) ?u8 {
        if (x >= self.width_in_cells or y >= self.height_in_cells) {
            return null;
        }
        return self.cells[y * self.width_in_cells + x];
    }

    pub fn renderAt(self: *const Self, writer: *std.Io.Writer, x: u16, y: u16) RenderError!void {
        try renderCells(
            writer,
            self.cells,
            self.width_in_cells,
            self.height_in_cells,
            x,
            y,
        );
    }

    pub fn renderWithAt(
        self: *const Self,
        writer: *std.Io.Writer,
        x: u16,
        y: u16,
        context: anytype,
        comptime Renderer: type,
    ) (RenderError || Renderer.Error)!void {
        try renderWithCells(
            writer,
            self.cells,
            self.width_in_cells,
            self.height_in_cells,
            x,
            y,
            context,
            Renderer,
        );
    }
};
