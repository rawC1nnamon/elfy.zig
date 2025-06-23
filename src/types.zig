const std = @import("std");
const constants = @import("constants.zig");

const elf = std.elf;
const meta = std.meta;

pub const ElfHeader = union(enum) {
    elf32: elf.Elf32_Ehdr,
    elf64: elf.Elf64_Ehdr,

    const Machine = constants.Machine;
    const Type = constants.Type;

    const Self = @This();

    pub fn getType(self: Self) Type {
        return switch (self) {
            inline else => |h| h.e_type,
        };
    }

    pub fn getMachine(self: Self) Machine {
        return switch (self) {
            inline else => |h| h.e_machine,
        };
    }

    pub fn getVersion(self: Self) u32 {
        return switch (self) {
            inline else => |h| h.e_version,
        };
    }

    pub fn getEntryPoint(self: Self) u64 {
        return switch (self) {
            inline else => |h| h.e_entry,
        };
    }

    pub fn getProgramHeaderOffset(self: Self) u64 {
        return switch (self) {
            inline else => |h| h.e_phoff,
        };
    }

    pub fn getSectionHeaderOffset(self: Self) u64 {
        return switch (self) {
            inline else => |h| h.e_shoff,
        };
    }

    pub fn getFlags(self: Self) u32 {
        return switch (self) {
            inline else => |h| h.e_flags,
        };
    }

    pub fn getSize(self: Self) u16 {
        return switch (self) {
            inline else => |h| h.e_ehsize,
        };
    }

    pub fn getProgramHeaderEntSize(self: Self) u16 {
        return switch (self) {
            inline else => |h| h.e_phentsize,
        };
    }

    pub fn getProgramHeaderCount(self: Self) u16 {
        return switch (self) {
            inline else => |h| h.e_phnum,
        };
    }

    pub fn getSectionHeaderEntSize(self: Self) u16 {
        return switch (self) {
            inline else => |h| h.e_shentsize,
        };
    }

    pub fn getSectionHeaderCount(self: Self) u16 {
        return switch (self) {
            inline else => |h| h.e_shnum,
        };
    }

    pub fn getSectionHeaderStringIndex(self: Self) u16 {
        return switch (self) {
            inline else => |h| h.e_shstrndx,
        };
    }

    pub fn getClass(self: Self) u8 {
        return switch (self) {
            inline else => |h| h.e_ident[elf.EI_CLASS],
        };
    }

    pub fn getData(self: Self) u8 {
        return switch (self) {
            inline else => |h| h.e_ident[elf.EI_DATA],
        };
    }

    pub fn getFormatVersion(self: Self) u8 {
        return switch (self) {
            inline else => |h| h.e_ident[elf.EI_VERSION],
        };
    }

    pub fn getOSABI(self: Self) constants.OSABI {
        return switch (self) {
            inline else => |h| @as(constants.OSABI, @enumFromInt(h.e_ident[elf.EI_OSABI])),
        };
    }

    pub fn getABIVersion(self: Self) u8 {
        return switch (self) {
            inline else => |h| h.e_ident[elf.EI_ABIVERSION],
        };
    }
};

pub const ElfProgram = union(enum) {
    elf32: elf.Elf32_Phdr,
    elf64: elf.Elf64_Phdr,

    const ProgType = constants.ProgType;
    const ProgFlag = constants.ProgFlag;

    const Self = @This();

    pub fn getType(self: Self) ProgType {
        return switch (self) {
            inline else => |p| meta.intToEnum(ProgType, p.p_type) catch ProgType.PT_UNKNOWN,
        };
    }

    pub fn getFlags(self: Self) ProgFlag {
        return switch (self) {
            inline else => |p| meta.intToEnum(ProgFlag, p.p_flags) catch ProgFlag.PF_UNKNOWN,
        };
    }

    pub fn getOffset(self: Self) u64 {
        return switch (self) {
            inline else => |p| p.p_offset,
        };
    }

    pub fn getVirtualAddress(self: Self) u64 {
        return switch (self) {
            inline else => |p| p.p_vaddr,
        };
    }

    pub fn getPhysicalAddress(self: Self) u64 {
        return switch (self) {
            inline else => |p| p.p_paddr,
        };
    }

    pub fn getFileSize(self: Self) u64 {
        return switch (self) {
            inline else => |p| p.p_filesz,
        };
    }

    pub fn getMemorySize(self: Self) u64 {
        return switch (self) {
            inline else => |p| p.p_memsz,
        };
    }

    pub fn getAlignment(self: Self) u64 {
        return switch (self) {
            inline else => |p| p.p_align,
        };
    }
};

pub const ElfSection = union(enum) {
    elf32: elf.Elf32_Shdr,
    elf64: elf.Elf64_Shdr,

    const SectionType = constants.SectionType;
    const SectionFlag = constants.SectionFlag;

    const Self = @This();

    pub fn getNameOffset(self: Self) u32 {
        return switch (self) {
            inline else => |s| s.sh_name,
        };
    }

    pub fn getType(self: Self) SectionType {
        return switch (self) {
            inline else => |s| meta.intToEnum(SectionType, s.sh_type) catch SectionType.SHT_UNKNOWN,
        };
    }

    pub fn getFlags(self: Self) SectionFlag {
        return switch (self) {
            inline else => |s| meta.intToEnum(SectionFlag, s.sh_flags) catch SectionFlag.SHF_UNKNOWN,
        };
    }

    pub fn getAddress(self: Self) u64 {
        return switch (self) {
            inline else => |s| s.sh_addr,
        };
    }

    pub fn getOffset(self: Self) u64 {
        return switch (self) {
            inline else => |s| s.sh_offset,
        };
    }

    pub fn getSize(self: Self) u64 {
        return switch (self) {
            inline else => |s| s.sh_size,
        };
    }

    pub fn getLink(self: Self) u32 {
        return switch (self) {
            inline else => |s| s.sh_link,
        };
    }

    pub fn getInfo(self: Self) u32 {
        return switch (self) {
            inline else => |s| s.sh_info,
        };
    }

    pub fn getAlignment(self: Self) u64 {
        return switch (self) {
            inline else => |s| s.sh_addralign,
        };
    }

    pub fn getEntrySize(self: Self) u64 {
        return switch (self) {
            inline else => |s| s.sh_entsize,
        };
    }
};

pub const ElfSymbol = union(enum) {
    elf32: elf.Elf32_Sym,
    elf64: elf.Elf64_Sym,

    const SymbolType = constants.SymbolType;
    const SymbolBind = constants.SymbolBind;

    const Self = @This();

    pub fn getNameOffset(self: Self) u32 {
        return switch (self) {
            inline else => |s| s.st_name,
        };
    }

    pub fn getInfo(self: Self) u8 {
        return switch (self) {
            inline else => |s| s.st_info,
        };
    }

    pub fn getOther(self: Self) u8 {
        return switch (self) {
            inline else => |s| s.st_other,
        };
    }

    pub fn getSectionIndex(self: Self) u16 {
        return switch (self) {
            inline else => |s| s.st_shndx,
        };
    }

    pub fn getValue(self: Self) u64 {
        return switch (self) {
            inline else => |s| s.st_value,
        };
    }

    pub fn getSize(self: Self) u64 {
        return switch (self) {
            inline else => |s| s.st_size,
        };
    }

    pub fn getBind(self: Self) SymbolBind {
        return switch (self) {
            inline else => |s| meta.intToEnum(SymbolBind, s.st_info >> 4) catch SymbolBind.STB_UNKNOWN,
        };
    }

    pub fn getType(self: Self) SymbolType {
        return switch (self) {
            inline else => |s| meta.intToEnum(SymbolType, s.st_info & 0xf) catch SymbolType.STT_UNKNOWN,
        };
    }

    pub fn getVisibility(self: Self) elf.STV {
        return switch (self) {
            inline else => |s| meta.intToEnum(elf.STV, s.st_other) catch elf.STV.DEFAULT,
        };
    }
};

pub const ElfDynamic = union(enum) {
    elf32: elf.Elf32_Dyn,
    elf64: elf.Elf64_Dyn,

    const DynTag = constants.DynTag;

    const Self = @This();

    pub fn getTag(self: Self) DynTag {
        return switch (self) {
            inline else => |d| meta.intToEnum(DynTag, d.d_tag) catch DynTag.DT_UNKNOWN,
        };
    }

    pub fn getValue(self: Self) u64 {
        return switch (self) {
            inline else => |d| d.d_val,
        };
    }
};

pub const ElfRelocation = union(enum) {
    rel: union(enum) {
        elf32: elf.Elf32_Rel,
        elf64: elf.Elf64_Rel,
    },

    rela: union(enum) {
        elf32: elf.Elf32_Rela,
        elf64: elf.Elf64_Rela,
    },

    const RelocationType = constants.RelocationType;
    const Machine = constants.Machine;

    const Self = @This();

    pub fn getOffset(self: Self) u64 {
        return switch (self) {
            inline else => |reloc| blk: {
                switch (reloc) {
                    inline else => |r| break :blk r.r_offset,
                }
            },
        };
    }

    pub fn getInfo(self: Self) u64 {
        return switch (self) {
            inline else => |reloc| blk: {
                switch (reloc) {
                    inline else => |r| break :blk r.r_info,
                }
            },
        };
    }

    pub fn getSymbolIndex(self: Self) u64 {
        return switch (self) {
            inline else => |reloc| blk: {
                switch (reloc) {
                    .elf32 => |r| break :blk r.r_info >> 8,
                    .elf64 => |r| break :blk r.r_info >> 32,
                }
            },
        };
    }

    pub fn getType(self: Self, machine: Machine) !RelocationType {
        return switch (self) {
            inline else => |reloc| {
                switch (reloc) {
                    inline else => |r| {
                        const info = if (reloc == .elf32) r.r_info & 0xFF else @as(u32, @intCast(r.r_info & 0xFFFFFFFF));

                        inline for (@typeInfo(RelocationType).@"union".fields) |field| {
                            if (std.mem.eql(u8, field.name, @tagName(machine))) {
                                return @unionInit(RelocationType, field.name, try std.meta.intToEnum(field.type, info));
                            }
                        }

                        return error.UnknownRelocationArch;
                    },
                }
            },
        };
    }

    pub fn getAddend(self: Self) ?i64 {
        return switch (self) {
            .rel => null,
            .rela => |rla| switch (rla) {
                inline else => |r| r.r_addend,
            },
        };
    }

    pub fn isRela(self: Self) bool {
        return switch (self) {
            .rel => false,
            .rela => true,
        };
    }
};
