const std = @import("std");

const MultibootInfo = extern struct {
    total_size: u32,
    reserved: u32,

    pub fn tagsLen(self: MultibootInfo) usize {
        return @as(usize, self.total_size) - @sizeOf(u64);
    }

    pub fn getTag(self: *const MultibootInfo, comptime T: type) ?*T {
        const tag_type = tagType(T);
        var current: *Tag = @ptrFromInt(@intFromPtr(self) + 8);

        while (!current.isEnd()) {
            if (current.type == tag_type) {
                return @fieldParentPtr(T, "base", current);
            }

            // next pointer (rounded up to 8-byte alignment)
            const ptr_offset: usize = (@as(usize, current.size) + 7) & ~@as(usize, 7);
            const curr_usize: usize = @intFromPtr(current);
            current = @ptrFromInt(curr_usize + ptr_offset);
        }

        return null;
    }
};

pub const Error = error{
    NullPtr,
    Misaligned,
    InvalidSize,
    InvalidEndTag,
};

pub fn init(address: usize) Error!*MultibootInfo {
    if (address == 0) {
        return Error.NullPtr;
    }

    if (address & 7 != 0) {
        return Error.Misaligned;
    }

    const info: *MultibootInfo = @ptrFromInt(address);

    if (info.total_size == 0 or (info.total_size & 0b111) != 0) {
        return Error.InvalidSize;
    }

    const tags = address + 8;
    const end: *Tag = @ptrFromInt(tags + info.tagsLen() - @sizeOf(Tag));
    if (!end.isEnd()) {
        return Error.InvalidEndTag;
    }

    return info;
}

fn tagType(comptime T: type) u32 {
    return switch (T) {
        BootCmdLine => 1,
        BootloaderName => 2,
        Modules => 3,
        BasicMemInfo => 4,
        BootDev => 5,
        MemMap => 6,
        VBE => 7,
        Framebuffer => 8,
        ElfSections => 9,
        APM => 10,
        else => @compileError("Invalid tag type"),
    };
}

pub const Tag = extern struct {
    type: u32,
    size: u32,

    pub fn isEnd(self: Tag) bool {
        return self.type == 0 and self.size == @sizeOf(Tag);
    }
};

pub const BootCmdLine = extern struct {
    base: Tag,
    string: [*:0]u8,
};

pub const BootloaderName = extern struct {
    base: Tag,
    string: [*:0]u8,
};

pub const Modules = extern struct {
    base: Tag,
    mod_start: u32,
    mod_end: u32,
    cmdline: [*:0]u8,
};

pub const BasicMemInfo = extern struct {
    base: Tag,
    mem_lower: u32,
    mem_upper: u32,
};

pub const BootDev = extern struct {
    base: Tag,
    biosdev: u32,
    slice: u32,
    part: u32,
};

pub const MemMap = extern struct {
    comptime {
        if (@sizeOf(MemMap) != 24) @compileError("Wrong MemMap size");
    }

    pub const Entry = extern struct {
        pub const AVAILABLE = 1;
        pub const RESERVED = 2;
        pub const ACPI_RECLAIMABLE = 3;
        pub const NVS = 4;

        address: u64,
        len: u64,
        type: u32,
        zero: u32,
    };

    pub fn areas(self: *const MemMap) []Entry {
        if (@sizeOf(Entry) != self.entry_size) @panic("Invalid Entry size");

        var entries: []Entry = undefined;

        const self_usize: usize = @intFromPtr(self);
        entries.ptr = @ptrFromInt(self_usize + 16);

        const size: usize = @as(usize, self.base.size) - @sizeOf(u32) * 4;

        if (size % @sizeOf(Entry) != 0) @panic("MemMap size mismatch");

        entries.len = size / @sizeOf(Entry);

        return entries;
    }

    base: Tag,
    entry_size: u32,
    entry_version: u32,
    entries: [*]Entry,
};

pub const VBE = extern struct {
    pub const InfoBlock = extern struct {
        external_specification: [512]u8,
    };

    pub const ModeInfoBlock = extern struct {
        external_specification: [256]u8,
    };

    base: Tag,
    mode: u16,
    interface_seg: u16,
    interface_off: u16,
    interface_len: u16,
    control_info: InfoBlock,
    mode_info: ModeInfoBlock,
};

pub const Framebuffer = extern struct {
    pub const Common = extern struct {
        base: Tag,
        address: u64,
        pitch: u32,
        width: u32,
        height: u32,
        bpp: u8,
        framebuffer_type: Type,
        reserved: u16,
    };

    pub const Type = enum(u8) {
        Indexed = 0,
        RGB = 1,
        EGA_Text = 2,
    };

    pub const IndexedColor = extern struct {
        pub const Palette = extern struct {
            r: u8,
            g: u8,
            b: u8,
        };

        colors: u32,
        palette: [*]Palette,
    };

    pub const RGBColor = extern struct {
        r_pos: u8,
        r_mask: u8,
        g_pos: u8,
        g_mask: u8,
        b_pos: u8,
        b_mask: u8,
    };

    pub const Color = extern union {
        indexed: IndexedColor,
        rgb: RGBColor,
    };

    common: Common,
    color: Color,
};

pub const ElfSections = extern struct {
    base: Tag,
    num: u32,
    entsize: u32,
    shndx: u32,
    sections: [*:0]u8,
};

pub const APM = extern struct {
    base: Tag,
    version: u16,
    cseg: u16,
    offset: u32,
    cseg_16: u16,
    dseg: u16,
    flags: u16,
    cseg_len: u16,
    cseg_16_len: u16,
    dseg_len: u16,
};
