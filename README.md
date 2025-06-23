# Fast and tiny ELF parsing library for Zig

**Elfy** is an ELF parsing library that uses **mmap** (multi-platform) to map files into memory for reading. It supports both 32-bit and 64-bit ELF formats and handles little/big-endian byte ordering.

## Install

First, you must fetch the `elfy` library for your project:

```bash
zig fetch --save git+https://github.com/rawC1nnamon/zig.elfy#master
```

Then, after `b.addExecutable(...)`, add the following code to your `build.zig`:

```zig
const elfy = b.dependency("elfy", .{
    .target = target,
    .optimize = optimize,
});

// Where 'exe' is your project executable
exe.root_module.addImport("elfy", elfy.module("elfy"));
```

## Basic Usage

Elfy offers a rich API that supports parsing the most relevant ELF data. The binary can be initialized in two modes: `.ReadOnly` or `.ReadWrite`. The latter allows basic section content modification and the creation of a new ELF with these changes.

```zig
const std = @import("std");
const elfy = @import("elfy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // The binary must be a variable
    var binary = try elfy.Elf.init("/bin/cat", .ReadOnly, allocator);
    defer binary.deinit();

    const header = binary.getHeader();
    std.debug.print("Entry {x}, Machine: {s}\n", .{ header.getEntryPoint(), @tagName(header.getMachine()) });

    // Iterator return values must also be variables
    var sections = try binary.getIterator(elfy.ElfSection);
    while (try sections.next()) |section| {
        const name = try binary.getSectionName(section);
        const section_type = section.getType();
        std.debug.print("Name: {s}, Type: {s}\n", .{ name, @tagName(section_type) });
    }
}
```

## Elf

`Elf` is the struct that contains the API and can be accessed this way: `elfy.Elf`. You must initialize the binary using the `init` function: `Elf.init(path: []const u8, mode: MapMode, allocator: Allocator)` (make sure to `deinit` the binary using `defer binary.deinit()`).

Elfy uses a hybrid parsing method (lazy and eager). Lightweight data, such as sections, string tables, and symbol names, are processed during `init`. On the other hand, data like symbol content, dynamic symbols, and relocations are lazily parsed using an `Iterator`, which you can obtain with the following function: `try binary.getIterator(...)`. This function accepts iterable data structures, which include:

* `ElfProgram`: Program/segment headers.  
* `ElfSection`: Section headers. 
* `ElfSymbol`: Symbol sections.
* `ElfDynamic`: Dynamic symbol sections.
* `ElfRelocation`: Relocation sections.  

```zig
// elfy.ElfProgram, elfy.ElfSection, elfy.ElfSymbol ...
var sections = try binary.getIterator(elfy.ElfSection);
while (try sections.next()) |section| {
    // ...
}
```

The **iterator** returned by `getIterator(...)` contains a `next()` function to retrieve the next data structure (you should use a `while` loop to iterate) and a `reset()` function to reset the iterator. Additionally, the iterator includes flow control fields like `index`, `remaining`, `count`, etc. Avoid modifying these fields.

Lastly, the **binary** instance returned by `init(...)` contains useful functions that facilitate parsing complex structures:

* `createElf(name: []const u8) ElfError!void`
* `getHeader() ElfHeader`
* `getIterator(comptime T: type) ElfError!Iterator(T)`
* `getSectionName(section: ElfSection) ElfError![]const u8`
* `getSectionData(section: ElfSection) ElfError![]const u8`
* `getSectionByIndex(index: u64) ElfError!ElfSection`
* `getSectionByName(name: []const u8) ElfError!ElfSection`
* `getSectionByType(section_type: SectionType) ElfError!ElfSection`
* `getSectionDataByName(name: []const u8) ElfError![]const u8`
* `modifySectionData(section: ElfSection, data: []const u8) ElfError!void`
* `getSymbolName(symbol: ElfSymbol) ElfError![]const u8`
* `getDynName(dynamic: ElfDynamic) ElfError!?[]const u8`
* `getRelocationLinkedSymbol(relocation: ElfRelocation, reloc_index: u64) ElfError!ElfSymbol`

## ELF Structures

Elfy contains six data structures: `ElfHeader`, `ElfProgram`, `ElfSection`, `ElfSymbol`, `ElfDynamic`, and `ElfRelocation`. These are tagged unions that contain both 32-bit and 64-bit fields, but you don't need to use `switch (...)` to access the content. Each data structure has methods to retrieve information (see [types](src/types.zig)). For example:

```zig
var symbols = try binary.getIterator(elfy.ElfSymbol);
while (try symbols.next()) |symbol| {
    _ = symbol.getInfo();
    _ = symbol.getSize();
    _ = symbol.getBind();
    _ = symbol.getType();
    _ = symbol.getVisibility();
    // ...
}
```

There is one special case: `relocation.getType(...)` receives a machine value as a parameter (for example, `header.getMachine()`) and returns a tagged union containing the relocation type for each architecture. You must use `switch (reloc_type)` to unpack it. For example:

```zig
const header = binary.getHeader();
var relocations = try binary.getIterator(elfy.ElfRelocation);
while (try relocations.next()) |relocation| {
    // relocation.getType() receives the ELF machine as parameter
    const linked_symbol = try binary.getRelocationLinkedSymbol(relocation, relocations.index);
    const symbol_name = try binary.getSymbolName(linked_symbol);
    const reloc_type = try relocation.getType(header.getMachine());
    
    switch (reloc_type) {
         .X86_64 => |t| std.debug.print("Type: {s}, Symbol Name: {s}\n", .{ @tagName(t), symbol_name }),
        // You can add more architectures if needed (ARM, RISCV, SPARC, etc.)
        else => std.debug.print("[!] Unsupported architecture", .{}),
    }
}
```

Supported relocation types are:

* `@"386"`
* `S390`
* `ARM`
* `PPC`
* `PPC64`
* `MIPS`
* `ALPHA`
* `AARCH64`
* `LOONGARCH`
* `RISCV`
* `SPARC`
* `X86_64`

## Modify Section Content

With the binary opened in `.ReadWrite` mode, you can modify the content of a section as long as the new content has a length less than or equal to the original buffer. For example:

```zig
const buf: []const u8 = &[_]u8{
    0x48, 0xc7, 0xc0, 0x01, 0x00, 0x00, 0x00,
    0x48, 0xc7, 0xc7, 0x01, 0x00, 0x00, 0x00,
    0x48, 0x8d, 0x35, 0x0a, 0x00, 0x00, 0x00,
    0x48, 0xc7, 0xc2, 0x0c, 0x00, 0x00, 0x00,
    0x0f, 0x05, 0x48, 0xc7, 0xc0, 0x3c, 0x00,
    0x00, 0x00, 0x48, 0xc7, 0xc7, 0x00, 0x00,
    0x00, 0x00, 0x0f, 0x05, 0x48, 0x65, 0x6c,
    0x6c, 0x6f, 0x20, 0x77, 0x6f, 0x72, 0x6c,
    0x64,
    0x0a,
    // ...
};

const text = try binary.getSectionByName(".text");
try binary.modifySectionData(text, buf);
try binary.createElf("new_binary");
```

## What If I Need Other Data Structures?

I created this library with the features I needed. If you're looking for a data structure that this parser doesn't contain (e.g., `ElfNote`, `relr`, etc.), you can create custom functions to parse it more easily. For example, if you want to parse notes:

```zig
fn parseNote(note: []const u8) !elf.Elf64_Nhdr { ... }
// ...

var sections = try binary.getIterator(elfy.ElfSection);
while (try sections.next()) |section| {
    const raw_note = if (section.getType() == .SHT_NOTE) try binary.getSectionData(section);
    const note = try parseNote(raw_note);
}
```
