/// Y:X
/// width 3 height 5
pub const blocks: [12]u15 = .{
    0b111101101101111, // 0
    0b110010010010111, // 1
    0b111001111100111, // 2
    0b111001111001111, // 3
    0b101101111001001, // 4
    0b111100111001111, // 5
    0b111100111101111, // 6
    0b111001010010010, // 7
    0b111101111101111, // 8
    0b111101111001001, // 9
    0b111101111101101, // A - 10
    0b111101111100100, // P - 11
};

// Normal colors
pub const default_highlight = "\x1b[48;5;8m";
pub const default_bold = "\x1b[38;5;231m";
pub const default_dim = "\x1b[38;5;238m";

// Red-tint
pub const redtint_highlight = "\x1b[48;5;52m";
pub const redtint_bold = "\x1b[1;38;5;196m";
pub const redtint_dim = "\x1b[38;5;238m";
