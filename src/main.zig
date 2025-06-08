const std = @import("std");
const zeit = @import("zeit");

const art = @import("ascii-art.zig");
const Termios = @import("termios.zig");
const Context = @import("context.zig");

var ctx = Context{};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    const local_tz = get_tz: {
        var env = try std.process.getEnvMap(alloc);
        defer env.deinit();

        break :get_tz try zeit.local(alloc, &env);
    };

    defer local_tz.deinit();

    const stdout = std.io.getStdOut();
    defer stdout.close();

    const stdin = std.io.getStdIn();
    defer stdin.close();

    var stdin_reader: std.io.BufferedReader(8, std.fs.File.Reader) = .{ .unbuffered_reader = stdin.reader() };

    {
        const args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);

        const help_fmt =
            \\Usage: {s} [-crd]
            \\
            \\  -c | Enable 12-hour clock
            \\  -r | Enable red-color mode
            \\  -d | Display the date and time
            \\
        ;

        for (args[1..]) |arg| {
            if (arg[0] != '-') _ = return try stdout.writer().print(help_fmt, .{args[0]});

            for (arg[1..]) |c| switch (c) {
                'c' => ctx.flags.am_pm = true, // 12 hour
                'r' => ctx.flags.red_tint = true, // red
                'd' => ctx.flags.show_date = true, // date
                else => {
                    return try stdout.writer().print(help_fmt, .{args[0]});
                },
            };
        }
    }

    const termios = try Termios.init();

    try termios.set();
    defer termios.reset() catch {};

    _ = try stdout.write("\x1b[?25l"); // Cursor visiblity
    defer _ = stdout.write("\x1b[?25h") catch {};

    _ = try stdout.write("\x1b[?1049h"); // Alternate buffer
    defer _ = stdout.write("\x1b[?1049l") catch {};

    {
        const size = try Termios.get_size();
        ctx.size.col.store(size.col, .unordered);
        ctx.size.row.store(size.row, .unordered);
    }

    const sigaction = std.posix.Sigaction{
        .handler = .{ .handler = sigaction_handler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };

    inline for ([_]comptime_int{
        std.posix.SIG.WINCH,
        std.posix.SIG.HUP,
        std.posix.SIG.INT,
        std.posix.SIG.TERM,
        std.posix.SIG.QUIT,
    }) |sig| {
        std.posix.sigaction(sig, &sigaction, null);
    }

    var last_day: u8 = 0xff;
    var last_second: u8 = 0xff;
    var buffer: [4]u8 = undefined;

    main: while (ctx.running.load(.acquire)) {
        const start = std.time.nanoTimestamp();

        // Input handling
        while (stdin_reader.reader().readByte() catch null) |byte| process_byte: switch (byte) {
            27, // escape
            => {
                const next_byte = stdin_reader.reader().readByte() catch break :main;
                if (next_byte != 'O' and next_byte != '[') continue :process_byte next_byte;
                _ = stdin_reader.reader().readByte() catch continue;
            },

            28, // ctrl \
            3, // ctrl c
            => break :main,

            else => {},
        };

        const now = try zeit.instant(.{ .timezone = &local_tz });
        const datetime = now.time();

        // Update
        if (ctx.size.changed.swap(false, .acquire) or last_day != datetime.day) {
            last_day = datetime.day;
            _ = try stdout.writeAll("\x1b[2J");
        }

        // Render
        if (last_second != datetime.second) {
            last_second = datetime.second;

            const is_am = datetime.hour <= 12;
            const numbers = print: {
                var hour = datetime.hour;

                if (ctx.flags.am_pm) {
                    if (is_am and hour == 0) hour = 12;
                    if (!is_am) hour -= 12;
                }

                break :print try std.fmt.bufPrint(buffer[0..4], "{d:0>2}{d:0>2}", .{ hour, datetime.minute });
            };

            const BLOCK_WIDTH = 3;
            const BLOCK_HEIGHT = 5;

            const x_mid_offset = 2;
            const x_mid = @divFloor(ctx.size.col.load(.acquire), 2) + x_mid_offset;
            const y_mid = @divFloor(ctx.size.row.load(.acquire), 2) - 1;

            const x_step: i8 = 3;
            const x_spacing = 10;

            const color_highlight = if (ctx.flags.red_tint) art.redtint_highlight else art.default_highlight;
            const color_bold = if (ctx.flags.red_tint) art.redtint_bold else art.default_bold;
            const color_dim = if (ctx.flags.red_tint) art.redtint_dim else art.default_dim;

            const writer = stdout.writer();

            // Draw hour and minute blocks
            for (0..4) |i| {
                const num = numbers[i] - '0'; // all inputs are between ascii 0 and ascii 9
                const current_art = art.blocks[num];

                const x_offset = (-x_spacing * 2) +
                    @as(isize, @intCast(x_spacing * i)) +
                    @as(isize, if (i < 2) -2 else 2);

                // Draw block
                for (0..BLOCK_HEIGHT) |y| for (0..BLOCK_WIDTH) |x| {
                    const art_bit_0: u15 = 0x4000;
                    const art_index: u4 = @intCast(y * BLOCK_WIDTH + x);
                    const representation: u6 = @intCast((BLOCK_WIDTH * BLOCK_HEIGHT * i) + (x * BLOCK_HEIGHT + y));

                    const highlight = if (representation == datetime.second) color_highlight else "";
                    const color = if (current_art & (art_bit_0 >> art_index) != 0) color_bold else color_dim;

                    try writer.print("\x1b[{d};{d}H" ++ "{s}{s}" ++ "{d:0>2}" ++ "\x1b[m", .{
                        y_mid + y,
                        x_mid + x_offset + @as(isize, @intCast(x)) * x_step,
                        highlight,
                        color,
                        representation,
                    });
                };
            }

            // Middle column
            const is_shown = @mod(datetime.second, 2) == 0;
            inline for ([2]usize{ 1, 3 }) |y| {
                try writer.print("\x1b[{d};{d}H", .{ y_mid + y, x_mid - x_mid_offset });
                try writer.print(
                    "{s}{s}",
                    if (is_shown)
                        .{ color_bold, "🬇🬃" }
                    else
                        .{ "", "  " },
                );
            }

            // AM / PM indicator
            if (ctx.flags.am_pm) {
                const x_offset = 4 + x_spacing * 2;

                for (0..BLOCK_HEIGHT) |y| for (0..BLOCK_WIDTH) |x| {
                    const art_bit_0: u15 = 0x4000;
                    const art_index: u4 = @intCast(y * BLOCK_WIDTH + x);

                    const current_art = art.blocks[if (is_am) 10 else 11];
                    const color = if (current_art & (art_bit_0 >> art_index) != 0) color_bold else color_dim;

                    try writer.print("\x1b[{d};{d}H" ++ "{s}" ++ "{s}" ++ "\x1b[m", .{
                        y_mid + y,
                        x_mid + x_offset + x * x_step,
                        color,
                        if (is_am) "am" else "pm",
                    });
                };
            }

            // Date string
            if (ctx.flags.show_date) {
                var weekday_month: [6]u8 = undefined;
                var fbs = std.io.fixedBufferStream(&weekday_month);
                try datetime.strftime(fbs.writer(), "%a%b");

                try writer.print("\x1b[{d};{d}H" ++
                    "{s}{s}" ++ "\x1b[m" ++
                    "{s}, {s} " ++ "\x1b[m" ++
                    "{s}{d} " ++ "\x1b[m" ++
                    "{s}{d}" ++ "\x1b[m", .{
                    y_mid + BLOCK_HEIGHT + 1,
                    x_mid - BLOCK_WIDTH * 6 - x_mid_offset * 2,
                    color_bold,
                    weekday_month[0..3],
                    color_dim,
                    weekday_month[3..6],
                    color_bold,
                    datetime.day,
                    color_dim,
                    datetime.year,
                });
            }
        }

        const end = std.time.nanoTimestamp();
        if (start >= end) continue;

        std.time.sleep(std.time.ns_per_ms * 125 - @as(u64, @intCast(end - start)));
    }
}

fn sigaction_handler(signal: i32) callconv(.C) void {
    switch (signal) {
        std.posix.SIG.WINCH => {
            const size = Termios.get_size() catch return;

            ctx.size.changed.store(true, .release);
            ctx.size.col.store(size.col, .release);
            ctx.size.row.store(size.row, .release);
        },
        std.posix.SIG.HUP,
        std.posix.SIG.INT,
        std.posix.SIG.TERM,
        std.posix.SIG.QUIT,
        => ctx.running.store(false, .release),
        else => unreachable,
    }
}
