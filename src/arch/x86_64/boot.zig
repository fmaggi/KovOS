const MultibootInfo = @import("multiboot2.zig");

comptime {
    _ = MultibootInfo;
}

const MultiBootHeader = extern struct {
    magic: u32,
    architecture: u32,
    header_length: u32,
    checksum: u32,
    endtag0: u32,
    endtag1: u32,
};

const MAGIC = 0xE85250D6;
const ARCH = 0;
const LEN = @sizeOf(MultiBootHeader);
const CHECKSUM = 0x100000000 - (MAGIC + 0 + LEN);

export var multiboot: MultiBootHeader align(4) linksection(".multiboot") = .{
    .magic = MAGIC,
    .architecture = ARCH,
    .header_length = LEN,
    .checksum = CHECKSUM,
    .endtag0 = 0,
    .endtag1 = 8,
};

extern fn kmain(address: usize) void;

export fn long_mode_start() callconv(.Naked) noreturn {
    asm volatile (
        \\ mov $0, %bx
        \\ mov %bx, %ss
        \\ mov %bx, %ds
        \\ mov %bx, %es
        \\ mov %bx, %fs
        \\ mov %bx, %gs
        \\ call kmain
    );

    while (true) {
        asm volatile ("hlt");
    }
}
