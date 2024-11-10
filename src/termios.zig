const std = @import("std");

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

    const rc = c_termios.tcgetattr(stdout, &original);
    try check_rc(rc);

    return Termios{
        .original = original,
    };
}

pub fn set(this: *const Termios) !void {
    var copy = this.original;
    c_termios.cfmakeraw(&copy);

    const rc = c_termios.tcsetattr(stdout, c_termios.TCSADRAIN, &copy);
    try check_rc(rc);

    const flags = c.fcntl(stdin, c.F_GETFL);
    const rc2 = c.fcntl(stdin, c.F_SETFL, flags | c.O_NONBLOCK);
    try check_rc(rc2);
}

pub fn reset(this: *const Termios) !void {
    const flags = c.fcntl(stdin, c.F_GETFL);
    const rc2 = c.fcntl(stdin, c.F_SETFL, flags & ~c.O_NONBLOCK);
    try check_rc(rc2);

    const rc = c_termios.tcsetattr(stdout, c_termios.TCSAFLUSH, &this.original);
    try check_rc(rc);
}

pub fn get_size() !c.winsize {
    var size: c.winsize = undefined;

    const rc = c.ioctl(stdout, c.TIOCGWINSZ, &size);
    try check_rc(rc);

    return size;
}

fn check_rc(rc: c_int) !void {
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        else => return error.Failed,
    }
}
