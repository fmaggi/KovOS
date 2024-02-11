const WIDTH = 80;
const HEIGHT = 25;

var vga: [*]ColoredChar = @ptrFromInt(0xB8000);

var X: u32 = 0;
var Y: u32 = 0;

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
        if (Y >= HEIGHT) @panic("Too much");
        X = 0;
        Y += 1;
        return;
    }

    const colored: ColoredChar = .{
        .color = color,
        .char = c,
    };
    vga[X + Y * WIDTH] = colored;
    X += 1;
}

pub fn write(str: []const u8, color: u8) void {
    for (str) |c| {
        putChar(c, color);
    }
}

pub fn set(pos_x: u32, pos_y: u32) void {
    X = pos_x;
    Y = pos_y;
}

pub fn reset() void {
    X = 0;
    Y = 0;
}
