const WIDTH = 80;
const HEIGHT = 25;

var vga: [*]ColoredChar = @ptrFromInt(0xB8000);

var x: u32 = 0;
var y: u32 = 0;

pub const ColoredChar = extern struct {
    char: u8,
    color: u8,
};

pub const Color = enum(u8) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    Pink = 13,
    Yellow = 14,
    White = 15,

    pub fn init(fg: Color, bg: Color) u8 {
        const f = @intFromEnum(fg);
        const b = @intFromEnum(bg);
        return (b << 4) | f;
    }
};

pub fn putChar(c: u8, color: u8) void {
    if (c == '\n') {
        if (y >= HEIGHT) @panic("Too much");
        x = 0;
        y += 1;
        return;
    }

    const colored: ColoredChar = .{
        .color = color,
        .char = c,
    };
    vga[x + y * WIDTH] = colored;
    x += 1;
}

pub fn write(str: []const u8, color: u8) void {
    for (str) |c| {
        putChar(c, color);
    }
}

pub fn set(pos_x: u32, pos_y: u32) void {
    x = pos_x;
    y = pos_y;
}

pub fn reset() void {
    x = 0;
    y = 0;
}
