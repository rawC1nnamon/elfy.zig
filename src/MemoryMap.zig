const Map = @This();

const std = @import("std");
const os = @import("builtin").os.tag;
const native_endian = @import("builtin").target.cpu.arch.endian();

const win = std.os.windows;
const posix = std.posix;
const fs = std.fs;
const mem = std.mem;

const Endian = std.builtin.Endian;

pub const MapMode = enum(u2) {
    ReadOnly = 0x1,
    ReadWrite = 0x2,
};

pub const MapError = error{
    UnexpectedEOF,
    FailedToCreateHandle,
    FailedToMapFile,
    InvalidOffset,
    MemoryMapNotMutable,
    NoMutableBuffer,
} || std.posix.WriteError || fs.File.OpenError || fs.File.StatError || posix.MMapError || fs.File.ReadError;

buffer: []const u8,
mut_buffer: ?[]u8,
mutable: bool,

hmap: ?win.HANDLE,
endian: Endian,

pub fn init(file: fs.File, endian: Endian, mode: MapMode) MapError!Map {
    const fd = file.handle;
    const stat = try file.stat();
    const mutable = mode == .ReadWrite;

    const FILE_MAP_WRITE = 0x0002;
    const FILE_MAP_READ = 0x0004;

    if (os == .windows) {
        const hMap = CreateFileMappingA(
            fd,
            null,
            if (!mutable) win.PAGE_READONLY else win.PAGE_READWRITE,
            0,
            0,
            null,
        ) orelse return MapError.FailedToCreateHandle;

        const buffer = MapViewOfFile(hMap, if (!mutable) FILE_MAP_READ else FILE_MAP_WRITE, 0, 0, 0);

        if (buffer) |buf_ptr| {
            const buf = @as([*]u8, @ptrCast(buf_ptr))[0..stat.size]; // *anyopaque as []u8
            const mut_buf = if (mutable) buf else null;

            return .{ .buffer = buf, .mut_buffer = mut_buf, .mutable = mutable, .hmap = hMap, .endian = endian };
        } else {
            _ = win.CloseHandle(hMap);
            return MapError.FailedToMapFile;
        }
    }

    // posix syscall
    const buf = try posix.mmap(null, stat.size, if (!mutable) std.posix.PROT.READ else std.posix.PROT.WRITE, .{ .TYPE = .PRIVATE }, fd, 0);
    errdefer posix.munmap(buf);

    const mut_buf = if (mutable) buf else null;

    return .{ .buffer = buf, .mut_buffer = mut_buf, .mutable = mutable, .hmap = null, .endian = endian };
}

pub fn deinit(self: *Map) void {
    if (self.buffer.len > 0) {
        if (os == .windows) {
            _ = UnmapViewOfFile(@as(win.LPCVOID, @ptrCast(@alignCast(self.buffer))));
            win.CloseHandle(self.hmap.?);
        } else posix.munmap(@ptrCast(@alignCast(self.buffer)));
    }
}

pub fn readBuffer(self: *Map, comptime T: type, offset: u64) MapError!T {
    if (offset + @sizeOf(T) > self.buffer.len) return MapError.InvalidOffset;

    const slice = self.buffer[offset..][0..@sizeOf(T)];
    var result: T = undefined;
    @memcpy(mem.asBytes(&result), slice);

    if (self.endian != native_endian) {
        mem.byteSwapAllFields(T, &result);
    }

    return result;
}

pub fn writeBuffer(self: *Map, bytes: []const u8, offset: u64) MapError!void {
    if (!self.mutable) return MapError.MemoryMapNotMutable;
    if (self.mut_buffer == null) return MapError.NoMutableBuffer;

    @memcpy(self.mut_buffer.?[@intCast(offset)..][0..bytes.len], bytes);
}

pub fn newFile(self: *Map, name: []const u8) MapError!void {
    const buf = self.mut_buffer orelse return MapError.NoMutableBuffer;

    const file = try fs.cwd().createFile(name, .{});
    defer file.close();

    try file.writeAll(buf); // TODO: Implement new writer API
}

extern "kernel32" fn CreateFileMappingA(
    hFile: win.HANDLE,
    lpFileMappingAttributes: ?*win.SECURITY_ATTRIBUTES,
    flProtect: win.DWORD,
    dwMaximumSizeHigh: win.DWORD,
    dwMaximumSizeLow: win.DWORD,
    lpName: ?win.LPCSTR,
) callconv(win.WINAPI) ?win.HANDLE;

extern "kernel32" fn MapViewOfFile(
    hFileMappingObject: win.HANDLE,
    dwDesiredAccess: win.DWORD,
    dwFileOffsetHigh: win.DWORD,
    dwFileOffsetLow: win.DWORD,
    dwNumberOfBytesToMap: win.SIZE_T,
) callconv(win.WINAPI) ?win.LPVOID;

extern "kernel32" fn UnmapViewOfFile(lpBaseAddress: win.LPCVOID) callconv(win.WINAPI) bool;
extern "kernel32" fn FlushViewOfFile(lpBaseAddress: win.LPCVOID, dwNumberOfBytesToFlush: win.SIZE_T) callconv(win.WINAPI) bool;
