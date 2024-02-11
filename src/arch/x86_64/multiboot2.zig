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
        entries.ptr = @ptrFromInt(self_usize + @sizeOf(MemMap));

        const size: usize = @as(usize, self.base.size) - @sizeOf(MemMap);

        if (size % @sizeOf(Entry) != 0) @panic("MemMap size mismatch");

        entries.len = size / @sizeOf(Entry);

        return entries;
    }

    base: Tag,
    entry_size: u32,
    entry_version: u32,
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
    entry_size: u32,
    shndx: u32,

    pub fn iterator(self: *const ElfSections) Section.Iterator {
        const string_section_offset: usize = self.shndx * self.entry_size;

        const self_usize: usize = @intFromPtr(self);
        const first_section_usize = self_usize + @sizeOf(ElfSections);

        return .{
            .string_section = @ptrFromInt(first_section_usize + string_section_offset),
            .current = @ptrFromInt(first_section_usize),
            .remaining = self.num - 1,
            .entry_size = self.entry_size,
        };
    }

    pub const Section = struct {
        inner: *const anyopaque,
        string_section: ?*const anyopaque,
        entry_size: u32,

        pub fn name(self: Section) []const u8 {
            // string_section is just a regular Section at a particular offset
            // Take advantage of that.
            const string_section: Section = .{
                .inner = self.string_section.?,
                .string_section = null,
                .entry_size = self.entry_size,
            };

            const addr = string_section.address() + self.name_index();

            const str: [*]const u8 = @ptrFromInt(addr);
            var len: usize = 0;
            while (str[len] != 0) {
                len += 1;
            }

            var slice: []const u8 = undefined;
            slice.ptr = str;
            slice.len = len;
            return slice;
        }

        pub fn name_index(self: Section) u64 {
            return self.get("name_index");
        }

        pub fn typ(self: Section) u64 {
            return self.get("typ");
        }

        pub fn flags(self: Section) u64 {
            return self.get("flags");
        }

        pub fn address(self: Section) u64 {
            return self.get("addr");
        }

        pub fn offset(self: Section) u64 {
            return self.get("offset");
        }

        pub fn size(self: Section) u64 {
            return self.get("size");
        }

        pub fn link(self: Section) u64 {
            return self.get("link");
        }

        pub fn info(self: Section) u64 {
            return self.get("info");
        }

        pub fn addralign(self: Section) u64 {
            return self.get("addralign");
        }

        fn get(self: Section, comptime field: []const u8) u64 {
            // Elf headers (for 64 bit, mayber for 32 bit too) are misaligned, so
            // ptr casting is UB. I have to do this mess to get it to work
            const ptr_usize: usize = @intFromPtr(self.inner);
            switch (self.entry_size) {
                40 => {
                    const fT = FieldType(Section32, field);
                    const field_offset = @offsetOf(Section32, field);
                    const field_ptr: [*]const u8 = @ptrFromInt(ptr_usize + field_offset);

                    var buf: [@sizeOf(fT)]u8 = @bitCast(@as(fT, 0));
                    @memcpy(&buf, field_ptr);
                    return @intCast(@as(fT, @bitCast(buf)));
                },
                64 => {
                    const fT = FieldType(Section64, field);
                    const field_offset = @offsetOf(Section64, field);
                    const field_ptr: [*]const u8 = @ptrFromInt(ptr_usize + field_offset);

                    var buf: [@sizeOf(fT)]u8 = @bitCast(@as(fT, 0));
                    @memcpy(&buf, field_ptr);
                    return @intCast(@as(fT, @bitCast(buf)));
                },
                else => @panic("Unkown elf section size"),
            }
        }

        fn FieldType(comptime T: type, comptime field: []const u8) type {
            const FieldEnum = std.meta.FieldEnum(T);
            const field_enum = std.meta.stringToEnum(FieldEnum, field) orelse @compileError("Unkown field");
            const field_info = std.meta.fieldInfo(T, field_enum);
            return field_info.type;
        }

        pub const Iterator = struct {
            string_section: *const anyopaque,
            current: *const anyopaque,
            remaining: u32,
            entry_size: u32,

            pub fn next(self: *Iterator) ?Section {
                if (self.remaining == 0) return null;

                const curret_usize: usize = @intFromPtr(self.current);
                const next_ptr: *const anyopaque = @ptrFromInt(curret_usize + self.entry_size);

                self.current = next_ptr;
                self.remaining -= 1;

                const current = self.current;

                return .{
                    .string_section = self.string_section,
                    .inner = current,
                    .entry_size = self.entry_size,
                };
            }
        };
    };

    const Section32 = extern struct {
        name_index: u32,
        typ: u32,
        flags: u32,
        addr: u32,
        offset: u32,
        size: u32,
        link: u32,
        info: u32,
        addralign: u32,
        entry_size: u32,
    };

    const Section64 = extern struct {
        name_index: u32,
        typ: u32,
        flags: u64,
        addr: u64,
        offset: u64,
        size: u64,
        link: u32,
        info: u32,
        addralign: u64,
        entry_size: u64,
    };
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
