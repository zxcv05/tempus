const std = @import("std");

// TODO(correctness): Use build.zig instead of cImport
const c = switch (@import("builtin").os.tag) {
    .linux, .macos => {
        @cImport({
            @cInclude("asm/termbits.h");
            @cInclude("sys/ioctl.h");
        });
    },
    else => @compileError("Unsupported OS"),
};

const stdout = std.posix.STDOUT_FILENO;
const stdin = std.posix.STDIN_FILENO;

const Termios = @This();

original: std.posix.termios,

pub fn init() !Termios {
    return Termios{
        .original = try std.posix.tcgetattr(stdout),
    };
}

/// Put stdout into raw mode
/// Set non-blocking on stdin
pub fn set(this: *const Termios) !void {
    const copy = make_raw(&this.original);
    try std.posix.tcsetattr(stdout, .DRAIN, copy);

    var flags = try std.posix.fcntl(stdin, std.posix.F.GETFL, 0);
    flags |= 1 << @bitOffsetOf(std.posix.O, "NONBLOCK");

    _ = try std.posix.fcntl(stdin, std.posix.F.SETFL, flags);
}

/// Reset stdout to state prior to raw mode
/// Unset non-blocking on stdin
pub fn reset(this: *const Termios) !void {
    var flags = try std.posix.fcntl(stdin, std.posix.F.GETFL, 0);
    flags &= ~@as(usize, 1 << @bitOffsetOf(std.posix.O, "NONBLOCK"));

    _ = try std.posix.fcntl(stdin, std.posix.F.SETFL, flags);

    try std.posix.tcsetattr(stdout, .FLUSH, this.original);
}

/// Query ioctl for window size
pub fn get_size() !Size {
    var size: std.posix.winsize = undefined;

    const rc = std.os.linux.ioctl(stdout, std.os.linux.T.IOCGWINSZ, @intFromPtr(&size));
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        else => return error.Failed,
    }

    return .{
        .col = size.ws_col,
        .row = size.ws_row,
    };
}

/// Minimal port of cfmakeraw
fn make_raw(original: *const std.posix.termios) std.posix.termios {
    var copy = original.*;

    copy.iflag.IGNBRK = false;
    copy.iflag.BRKINT = false;

    copy.lflag.ECHO = false;
    copy.lflag.ECHONL = false;
    copy.lflag.ICANON = false;
    copy.lflag.ISIG = false;

    copy.cflag.CSIZE = .CS8;

    return copy;
}

pub const Size = struct {
    col: u16,
    row: u16,
};
