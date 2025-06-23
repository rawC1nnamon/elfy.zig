const std = @import("std");
const elfy = @import("elfy");

const testing = std.testing;
const init = elfy.Elf.init;
const allocator = testing.allocator;

fn testHeader(header: elfy.ElfHeader, expected_header_info: anytype) !void {
    switch (header) {
        inline else => |h| {
            inline for (@typeInfo(@TypeOf(h)).@"struct".fields, 0..) |field, i| {
                const value = @field(h, field.name);
                const expected_value = expected_header_info[i];

                if (field.type == [16]u8) {
                    try testing.expectEqualSlices(u8, &expected_value, value[0..4]);
                } else try testing.expectEqual(expected_value, value);
            }
        },
    }
}

fn testNames(binary: *elfy.Elf, comptime T: type, expected_names: anytype) !void {
    var iter = try binary.getIterator(T);
    var index: usize = 0;
    while (try iter.next()) |value| {
        if (index == expected_names.len) return;
        defer index += 1;
        const name = switch (T) {
            elfy.ElfSection => try binary.getSectionName(value),
            elfy.ElfSymbol => try binary.getSymbolName(value),
            elfy.ElfRelocation => blk: {
                const symbol = try binary.getRelocationLinkedSymbol(value, iter.index);
                break :blk try binary.getSymbolName(symbol);
            },
            else => unreachable,
        };

        try testing.expect(std.mem.eql(u8, expected_names[index], name));
    }
}

fn testTypes(binary: *elfy.Elf, comptime T: type, expected_types: anytype) !void {
    var iter = try binary.getIterator(T);
    var index: usize = 0;
    while (try iter.next()) |value| {
        if (index == expected_types.len) return;
        defer index += 1;
        const value_type = switch (T) {
            elfy.ElfDynamic => value.getTag(),
            else => value.getType(),
        };
        try testing.expectEqual(expected_types[index], value_type);
    }
}

test "parse ELF header and sections for x86_64 little-endian binary (cat)" {
    var binary = try init("test/x86_64_cat_ltendian", .ReadOnly, allocator);
    defer binary.deinit();

    const expected_header_info = .{
        [_]u8{ 0x7f, 'E', 'L', 'F' }, // magic
        elfy.Type.DYN, // e_type
        elfy.Machine.X86_64, // e_machine
        0x01, // e_version
        0x3880, // e_entry
        64, // e_phoff
        37296, // e_shoff
        0x0, // e_flags
        64, // e_ehsize
        56, // e_phentsize
        14, // e_phnum
        64, // e_shentsize
        28, // e_shnum
        27, // e_shstrndx
    };
    try testHeader(binary.header, &expected_header_info);

    const ProgType = elfy.ProgType;
    const expected_segments_types = [_]ProgType{
        .PT_PHDR,      .PT_INTERP,       .PT_LOAD,
        .PT_LOAD,      .PT_LOAD,         .PT_LOAD,
        .PT_DYNAMIC,   .PT_NOTE,         .PT_NOTE,
        .PT_NOTE,      .PT_GNU_PROPERTY, .PT_GNU_EH_FRAME,
        .PT_GNU_STACK, .PT_GNU_RELRO,
    };
    try testTypes(&binary, elfy.ElfProgram, &expected_segments_types);

    // First ten sections name
    const expected_sections_names = [_][]const u8{ "", ".note.gnu.property", ".note.gnu.build-id", ".interp", ".gnu.hash", ".dynsym", ".dynstr", ".gnu.version", ".gnu.version_r", ".rela.dyn" };
    try testNames(&binary, elfy.ElfSection, &expected_sections_names);

    // First ten symbols name
    const expected_symbol_names = [_][]const u8{
        "",                 "__progname",        "free",
        "__vfprintf_chk",   "__libc_start_main", "abort",
        "__errno_location", "strncmp",           "_ITM_deregisterTMCloneTable",
        "stdout",
    };
    try testNames(&binary, elfy.ElfSymbol, &expected_symbol_names);

    const DynTag = elfy.DynTag;
    const expected_dyns_type = [_]DynTag{
        .DT_NEEDED,       .DT_INIT,         .DT_FINI,
        .DT_INIT_ARRAY,   .DT_INIT_ARRAYSZ, .DT_FINI_ARRAY,
        .DT_FINI_ARRAYSZ, .DT_GNU_HASH,     .DT_STRTAB,
        .DT_SYMTAB,       .DT_STRSZ,        .DT_SYMENT,
        .DT_DEBUG,        .DT_RELA,         .DT_RELASZ,
        .DT_RELAENT,      .DT_FLAGS,        .DT_FLAGS_1,
        .DT_VERNEED,      .DT_VERNEEDNUM,   .DT_VERSYM,
        .DT_RELR,         .DT_RELRSZ,       .DT_RELRENT,
        .DT_NULL,
    };
    try testTypes(&binary, elfy.ElfDynamic, expected_dyns_type);

    // First ten linked symbols name
    const expected_reloc_linked_names = [_][]const u8{ "free", "__vfprintf_chk", "__libc_start_main", "abort", "__errno_location", "strncmp", "_ITM_deregisterTMCloneTable", "stdout", "_exit", "__fpending" };
    try testNames(&binary, elfy.ElfRelocation, &expected_reloc_linked_names);
}

test "parse ELF header and sections for SPARC big-endian binary (ls)" {
    var binary = try init("test/sparc_ls_bgendian", .ReadOnly, allocator);
    defer binary.deinit();

    const expected_header_info = .{
        [_]u8{ 0x7f, 'E', 'L', 'F' }, // magic
        elfy.Type.EXEC, // e_type
        elfy.Machine.SPARC, // e_machine
        0x1, // e_version
        0x12d28, // e_entry
        52, // e_phoff
        399916, // e_shoff
        0x0, // e_flags
        52, // e_ehsize
        32, // e_phentsize
        5, // e_phnum
        40, // e_shentsize
        38, // e_shnum
        37, // e_shstrndx
    };
    try testHeader(binary.header, expected_header_info);

    const ProgType = elfy.ProgType;
    const expected_segments_types = [_]ProgType{
        .PT_PHDR,    .PT_INTERP,
        .PT_LOAD,    .PT_LOAD,
        .PT_DYNAMIC,
    };
    try testTypes(&binary, elfy.ElfProgram, &expected_segments_types);

    // First ten sections name
    const expected_sections_names = [_][]const u8{
        "",          ".interp",       ".hash",     ".dynsym",
        ".dynstr",   ".SUNW_version", ".rela.got", ".rela.bss",
        ".rela.plt", ".text",
    };
    try testNames(&binary, elfy.ElfSection, &expected_sections_names);

    // First ten symbols name
    const expected_symbol_names = [_][]const u8{
        "",        "realloc", "nstrftime",          "argmatch_to_argument",
        "xzalloc", "memchr",  "hash_get_n_entries", "_obstack_begin",
        "environ", "strncmp",
    };
    try testNames(&binary, elfy.ElfSymbol, &expected_symbol_names);

    // First ten dyns type
    const DynTag = elfy.DynTag;
    const expected_dyns_type = [_]DynTag{
        .DT_NEEDED, .DT_NEEDED, .DT_NEEDED,
        .DT_INIT,   .DT_FINI,   .DT_RUNPATH,
        .DT_RPATH,  .DT_HASH,   .DT_STRTAB,
        .DT_STRSZ,
    };
    try testTypes(&binary, elfy.ElfDynamic, expected_dyns_type);

    // First ten linked symbols name
    const expected_reloc_linked_names = [_][]const u8{
        "__deregister_frame_info", "__register_frame_info",
        "_Jv_RegisterClasses",     "_environ",
        "__iob",                   "errno",
        "__ctype",                 "tzname",
        "atexit",                  "exit",
    };
    try testNames(&binary, elfy.ElfRelocation, &expected_reloc_linked_names);
}
