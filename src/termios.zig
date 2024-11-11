const std = @import("std");

// TODO(correctness): Use build.zig instead of cImport
const c = @cImport({
    @cInclude("asm/termbits.h");
    @cInclude("sys/ioctl.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
});

const c_termios = @cImport({
    @cInclude("termios.h");
});

const stdout = c.STDOUT_FILENO;
const stdin = c.STDIN_FILENO;

const Termios = @This();

original: c_termios.termios,

pub fn init() !Termios {
    var original: c_termios.termios = undefined;

    try wrap_posix_return(
        c_termios.tcgetattr(stdout, &original),
    );

    return Termios{
        .original = original,
    };
}

/// Put stdout into raw mode
/// Set non-blocking on stdin
pub fn set(this: *const Termios) !void {
    var copy = this.original;
    c_termios.cfmakeraw(&copy);

    try wrap_posix_return(
        c_termios.tcsetattr(stdout, c_termios.TCSADRAIN, &copy),
    );

    const flags = c.fcntl(stdin, c.F_GETFL);
    try wrap_posix_return(
        c.fcntl(stdin, c.F_SETFL, flags | c.O_NONBLOCK),
    );
}

/// Reset stdout to state prior to raw mode
/// Unset non-blocking on stdin
pub fn reset(this: *const Termios) !void {
    const flags = c.fcntl(stdin, c.F_GETFL);
    try wrap_posix_return(
        c.fcntl(stdin, c.F_SETFL, flags & ~c.O_NONBLOCK),
    );

    try wrap_posix_return(
        c_termios.tcsetattr(stdout, c_termios.TCSAFLUSH, &this.original),
    );
}

/// Query ioctl for window size
pub fn get_size() !c.winsize {
    var size: c.winsize = undefined;
    try wrap_posix_return(
        c.ioctl(stdout, c.TIOCGWINSZ, &size),
    );
    return size;
}

inline fn wrap_posix_return(rc: c_int) !void {
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        else => return error.Failed,
    }
}
