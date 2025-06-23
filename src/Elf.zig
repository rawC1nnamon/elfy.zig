const Elf = @This();

const std = @import("std");
const types = @import("types.zig");
const constants = @import("constants.zig");
const MemoryMap = @import("MemoryMap.zig");

const elf = std.elf;
const fs = std.fs;
const mem = std.mem;
const assert = std.debug.assert;

const Allocator = mem.Allocator;
const ElfHeader = types.ElfHeader;
const ElfProgram = types.ElfProgram;
const ElfSection = types.ElfSection;
const ElfSymbol = types.ElfSymbol;
const ElfDynamic = types.ElfDynamic;
const ElfRelocation = types.ElfRelocation;

const MapMode = MemoryMap.MapMode;
const MapError = MemoryMap.MapError;

const ElfError = error{
    EndOfStream,
    InvalidElfEndian,
    InvalidClass,
    NoSectionStringTable,
    EmptySection,
    InvalidSectionIndex,
    SectionNotFound,
    SymbolNameNotFound,
    DynStringTableNotFound,
    InvalidNameOffset,
    CannotGetEntries,
    CannotGetRelocationUnion,
    CannotGetUnion,
    InvalidLinkIndex,
    InvalidLinkedSection,
} || MapError;

file: fs.File,
reader: MemoryMap,
bits: []const u8,

header: ElfHeader,

// Preload caches for expensive operations
section_cache: std.AutoHashMap(u64, ElfSection),
symbol_name_cache: std.AutoHashMap(u64, []const u8),

// String tables
shstrtab: ?[]const u8 = null,
strtab: ?[]const u8 = null,
dynstr: ?[]const u8 = null,

allocator: Allocator,

pub fn init(path: []const u8, mode: MapMode, allocator: Allocator) ElfError!Elf {
    const file = try fs.cwd().openFile(path, .{});
    errdefer file.close();

    const e_ident = file.reader().readBytesNoEof(elf.EI_NIDENT) catch return ElfError.EndOfStream;
    assert(mem.eql(u8, e_ident[0..4], elf.MAGIC));

    const endian: std.builtin.Endian = switch (e_ident[elf.EI_DATA]) {
        1 => .little, // ELFDATA2LSB
        2 => .big, // ELFDATA2MSB
        else => return ElfError.InvalidElfEndian,
    };

    var Reader = try MemoryMap.init(file, endian, mode);
    errdefer Reader.deinit();
    assert(Reader.buffer.len > 0);

    const header = switch (e_ident[elf.EI_CLASS]) {
        elf.ELFCLASS32 => blk: {
            const buf = try Reader.readBuffer(elf.Elf32_Ehdr, 0);
            break :blk ElfHeader{ .elf32 = buf };
        },
        elf.ELFCLASS64 => blk: {
            const buf = try Reader.readBuffer(elf.Elf64_Ehdr, 0);
            break :blk ElfHeader{ .elf64 = buf };
        },
        else => return ElfError.InvalidClass,
    };

    const bits = if (header.getClass() == 1) "32" else "64";
    var Instance = Elf{
        .file = file,
        .reader = Reader,
        .bits = bits,
        .allocator = allocator,
        .header = header,
        .section_cache = std.AutoHashMap(u64, ElfSection).init(allocator),
        .symbol_name_cache = std.AutoHashMap(u64, []const u8).init(allocator)
    };

    // Generate cache using the elf instance

    var sections = try Instance.getIterator(ElfSection);
    while (try sections.next()) |section| {
        try Instance.section_cache.put(sections.index - 1, section);
    }

    const shstrtab_index = Instance.header.getSectionHeaderStringIndex();
    const shstrtab_section = try Instance.getSectionByIndex(shstrtab_index);

    Instance.shstrtab = Instance.getSectionData(shstrtab_section) catch null;
    Instance.strtab = Instance.getSectionDataByName(".strtab") catch null;
    Instance.dynstr = Instance.getSectionDataByName(".dynstr") catch null;

    var symbols = try Instance.getIterator(ElfSymbol);
    while (try symbols.next()) |symbol| {
        const name_offset = symbol.getNameOffset();

        if (Instance.strtab) |strtab| {
            const name = readNameFromTable(strtab, name_offset) catch null;
            if (name) |n| try Instance.symbol_name_cache.put(name_offset, n);
        }

        if (Instance.dynstr) |dynstr| {
            const name = readNameFromTable(dynstr, name_offset) catch null;
            if (name) |n| try Instance.symbol_name_cache.put(name_offset, n);
        }
    }

    return Instance;
}

pub fn deinit(self: *Elf) void {
    self.symbol_name_cache.deinit();
    self.section_cache.deinit();
    self.reader.deinit();
    self.file.close();
}

// Create a new elf with the changes that were applied to the buffer (if any)
pub fn createElf(self: *Elf, name: []const u8) ElfError!void {
    try self.reader.newFile(name);
}

pub inline fn getHeader(self: *Elf) ElfHeader {
    return self.header;
}

// Returns an iterator based on the parameter
pub fn getIterator(self: *Elf, comptime T: type) ElfError!Iterator(T) {
    return switch (T) {
        inline else => blk: {
            if (T == ElfProgram or T == ElfSection) break :blk try HeaderIterator(T).init(self);

            const args = switch (T) {
                ElfSymbol => &[_]constants.SectionType{ .SHT_SYMTAB, .SHT_DYNSYM },
                ElfDynamic => &[_]constants.SectionType{.SHT_DYNAMIC},
                ElfRelocation => &[_]constants.SectionType{ .SHT_REL, .SHT_RELA },
                // maybe add more sections
                else => unreachable,
            };

            break :blk try SectionIterator(T).init(self, args);
        },
    };
}

// Returns the section name using shstrtab
pub fn getSectionName(self: *Elf, section: ElfSection) ElfError![]const u8 {
    const table = self.shstrtab orelse return ElfError.NoSectionStringTable;
    return try readNameFromTable(table, section.getNameOffset());
}

// Returns an immutable section data buffer
pub fn getSectionData(self: *Elf, section: ElfSection) ElfError![]const u8 {
    const offset = section.getOffset();
    const size = section.getSize();

    if (size == 0) return ElfError.EmptySection;
    assert(offset + size <= self.reader.buffer.len);

    return self.reader.buffer[offset..][0..size];
}

// Returns the section by its index
pub fn getSectionByIndex(self: *Elf, index: u64) ElfError!ElfSection {
    return self.section_cache.get(index) orelse error.InvalidSectionIndex;
}

// Returns the section by its name
pub fn getSectionByName(self: *Elf, name: []const u8) ElfError!ElfSection {
    var sections = self.section_cache.iterator();
    while (sections.next()) |section_ptr| {
        const section = section_ptr.value_ptr.*;
        const section_name = try self.getSectionName(section);
        if (mem.eql(u8, section_name, name)) return section;
    }

    return ElfError.SectionNotFound;
}

// Returns the first section that matches the specified type
pub fn getSectionByType(self: *Elf, section_type: constants.SectionType) ElfError!ElfSection {
    var sections = self.section_cache.iterator();
    while (sections.next()) |section_ptr| {
        const section = section_ptr.value_ptr.*;
        if (section.getType() == section_type) return section;
    }

    return ElfError.SectionNotFound;
}

// Returns the section data by its name
pub fn getSectionDataByName(self: *Elf, name: []const u8) ElfError![]const u8 {
    const section = try self.getSectionByName(name);
    return try self.getSectionData(section);
}

// Allows editing the section data if the new buffer’s size is less than or equal to the section size
pub fn modifySectionData(self: *Elf, section: ElfSection, data: []const u8) ElfError!void {
    if (section.getSize() <= 0) return ElfError.EmptySection;
    assert(data.len < section.getSize());
    try self.reader.writeBuffer(data, section.getOffset());
}

// Returns the symbol name through strtab or dynstr
pub fn getSymbolName(self: *Elf, symbol: ElfSymbol) ElfError![]const u8 {
    const name_offset = symbol.getNameOffset();
    return self.symbol_name_cache.get(name_offset) orelse ElfError.SymbolNameNotFound;
}

// Returns the dynamic symbol name using dynstr
pub fn getDynName(self: *Elf, dynamic: ElfDynamic) ElfError!?[]const u8 {
    const dynstr = self.dynstr orelse return ElfError.DynStringTableNotFound;

    // If the dynamic tag has an associated name, return it, otherwise, return null
    return switch (dynamic.getTag()) {
        .DT_NEEDED, .DT_SONAME, 
        .DT_RPATH, .DT_RUNPATH, 
        .DT_AUXILIARY, .DT_FILTER, 
        .DT_CONFIG, .DT_DEPAUDIT, .DT_AUDIT => try readNameFromTable(dynstr, dynamic.getValue()),
        else => null,
    };
}

// Returns the relocation’s linked symbol using the actual section index
pub fn getRelocationLinkedSymbol(self: *Elf, relocation: ElfRelocation, index: u64) ElfError!ElfSymbol {
    const section = try self.getSectionByIndex(index);
    const symtab_index = section.getLink();
    if (symtab_index >= self.header.getSectionHeaderCount()) return ElfError.InvalidLinkIndex;

    const linked_section = try self.getSectionByIndex(symtab_index);
    if (linked_section.getType() != .SHT_SYMTAB and linked_section.getType() != .SHT_DYNSYM) return ElfError.InvalidLinkedSection;

    const sym_idx = relocation.getSymbolIndex();
    const sym_offset = linked_section.getOffset() + sym_idx * linked_section.getEntrySize();

    return try self.getUnionByArch(ElfSymbol, sym_offset);
}

// Returns the name from the given string table using the offset
fn readNameFromTable(table: []const u8, offset: u64) ElfError![]const u8 {
    if (offset >= table.len) return ElfError.InvalidNameOffset;
    return mem.sliceTo(table[offset..], 0);
}

const IteratorError = error{
    CannotGetEntries,
    CannotGetRelocationUnion,
} || ElfError;

// A generic function to return any iterator
fn Iterator(comptime T: type) type {
    return switch (T) {
        ElfProgram, ElfSection => HeaderIterator(T),
        ElfSymbol, ElfDynamic, ElfRelocation => SectionIterator(T),
        else => @compileError("Unsupported type for Iterator: " ++ @typeName(T)),
    };
}

// A generic function to iterate elf headers
fn HeaderIterator(comptime T: type) type {
    return struct {
        binary: *Elf,
        remaining: u64,
        index: u64 = 0,

        const Self = @This();

        pub fn init(binary: *Elf) IteratorError!Self {
            const total = if (T == ElfSection)
                binary.header.getSectionHeaderCount()
            else if (T == ElfProgram)
                binary.header.getProgramHeaderCount()
            else
                return IteratorError.CannotGetEntries;

            return .{
                .binary = binary,
                .remaining = total,
            };
        }

        pub fn next(self: *Self) IteratorError!?T {
            if (self.index >= self.remaining) return null;
            const header = self.binary.header;
            defer self.index += 1;

            const entry_size = if (T == ElfSection)
                header.getSectionHeaderEntSize()
            else
                header.getProgramHeaderEntSize();

            const offset = if (T == ElfSection)
                header.getSectionHeaderOffset() + entry_size * self.index
            else
                header.getProgramHeaderOffset() + entry_size * self.index;

            return try self.binary.getUnionByArch(T, offset);
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
        }
    };
}

// A generic function to iterate elf sections
fn SectionIterator(comptime T: type) type {
    return struct {
        binary: *Elf,
        remaining: u64,
        args: []const SectionType,
        index: u64 = 0,
        count: u64 = 0,

        const SectionType = constants.SectionType;
        const Self = @This();

        pub fn init(binary: *Elf, args: []const SectionType) IteratorError!Self {
            var total: u64 = 0;
            var sections = binary.section_cache.iterator();
            while (sections.next()) |section_ptr| {
                const section = section_ptr.value_ptr.*;
                for (args) |arg| {
                    if (section.getType() == arg) {
                        if (section.getEntrySize() > 0) total += section.getSize() / section.getEntrySize();
                    } else continue;
                }
            }

            return .{ .binary = binary, .remaining = total, .args = args };
        }

        pub fn next(self: *Self) IteratorError!?T {
            if (self.remaining == 0) return null;
            const binary = self.binary;

            while (self.index < binary.header.getSectionHeaderCount()) {
                const section = try binary.getSectionByIndex(self.index);
                const ent_size = section.getEntrySize();

                var reloc_name: []const u8 = undefined;
                const match = for (self.args) |arg| {
                    if (section.getType() == arg) {
                        reloc_name = if (arg == .SHT_REL) "rel" else "rela";
                        break true;
                    }
                } else false;

                if (!match or ent_size == 0) {
                    self.index += 1;
                    continue;
                }

                if (self.count < section.getSize() / ent_size) {
                    defer self.count += 1;
                    defer self.remaining -= 1;

                    const offset = section.getOffset() + ent_size * self.count;
                    if (T == ElfRelocation) return try self.getUnionRelocByPattern(reloc_name, offset);
                    return try self.binary.getUnionByArch(T, offset);
                }

                self.index += 1;
                self.count = 0;
            } else return null;
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
            self.remaining = self.count;
            self.count = 0;
        }

        // Returns a relocation union type based on a pattern
        fn getUnionRelocByPattern(self: *Self, pattern: []const u8, init_buf_offset: u64) IteratorError!T {
            inline for (@typeInfo(T).@"union".fields) |field| {
                if (mem.indexOf(u8, field.name, pattern) != null) {
                    const relocation = try self.binary.getUnionByArch(field.type, init_buf_offset);
                    return @unionInit(T, field.name, relocation);
                }
            } else return IteratorError.CannotGetRelocationUnion;
        }
    };
}

// Returns a T union type based on the binary bits
fn getUnionByArch(self: *Elf, comptime T: type, init_buf_offset: u64) ElfError!T {
    inline for (@typeInfo(T).@"union".fields) |field| {
        if (mem.indexOf(u8, field.name, self.bits) != null) {
            assert(init_buf_offset <= self.reader.buffer.len);
            const buf = try self.reader.readBuffer(field.type, init_buf_offset);
            return @unionInit(T, field.name, buf);
        }
    } else return ElfError.CannotGetUnion;
}
