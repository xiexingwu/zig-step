const Note = @This();
pub const Note0 = Note{}; // Sentinel

const std = @import("std");
const rl = @import("raylib");
const sm = @import("./simfile.zig");
const log = std.log;

pub const NoteType = enum(u8) {
    sentinel = '0',
    note,
    hold,
    tail,
    roll,
    mine = 'M',
    fake = 'F',
};

type: NoteType = .sentinel,

// bit-wise indication of active columns
// For SP: only the 4 LSBs are used, with MSB being left, LSB being right
// For DP: MSB is p1-left, LSB is p2-right
columns: u8 = 0,

denominator: u8 = 0, // # of lines measure is broken into: 4 = quarter notes, 8 = eighth notes etc.
numerator: u8 = 0, // line of appearance (0-indexed)
measure: u8 = 0, // measure (0-indexed)
time: f32 = 0, // arrival time (sec)

pub fn getColumnChar(self: Note) u8 {
    return switch (self.columns) {
        1 << 7 => 'L',
        1 << 6 => 'D',
        1 << 5 => 'U',
        1 << 4 => 'R',
        1 << 3 => 'l',
        1 << 2 => 'd',
        1 << 1 => 'u',
        1 << 0 => 'r',
        else => unreachable,
    };
}

pub fn getMeasBeat(self: Note) f32 {
    const den: f32 = @floatFromInt(self.denominator);
    const num: f32 = @floatFromInt(self.numerator);
    return 4.0 * num / den;
}

pub fn getSongBeat(self: Note) f32 {
    const meas: f32 = @floatFromInt(self.measure);
    return 4.0 * meas + getMeasBeat(self);
}

pub fn getColor(self: Note) rl.Color {
    switch (self.type) {
        .tail, .roll, .mine, .fake => {
            return rl.Color.blank;
        },
        .sentinel => unreachable,
        else => {},
    }

    // Special handling for cases when there are no eighth notes:
    // Currently only 1/3 notes for 6-row measures
    if (self.denominator % 4 > 0) {
        return if (self.numerator % 3 == 0) rl.Color.red else rl.Color.green;
    }

    const subdivs = self.denominator / 4; // subdivisions of a sigle beat
    const measBeat = 4 * self.numerator / self.denominator;
    const subdiv = self.numerator - measBeat * subdivs; // Find which subdiv note is in
    if (subdiv == 0) return rl.Color.red;

    const gcd = std.math.gcd(subdiv, subdivs);
    // Examples:
    // subdivs: 2 - b
    // subdivs: 3 - g G
    // subdivs: 4 - y b y
    //     gcd:     1 2 1
    // subdivs: 8 - o y o b o y o
    //     gcd:     1 2 1 4 1 2 1
    //   quant:     8 4 8 2 8 4 8
    // subdivs: 12 - x g y G x b x g y G x
    //     gcd:      1 2 3 4 1 6 1 4 3 2 1
    //   quant:      x 6 4 3 x 2 x 3 4 6 x
    const quant = subdivs / gcd;
    return switch (quant) {
        2 => rl.Color.blue,
        3 => rl.Color.green,
        4 => rl.Color.yellow,
        6 => rl.Color.sky_blue,
        8 => rl.Color.orange,
        else => rl.Color.dark_green,
    };
}
pub fn hasColumn(self: Note, colNum: u3) bool {
    return self.note & getColumn(colNum) > 0;
}

pub fn getColumnNum(col: u8) u3 {
    std.debug.assert(std.math.isPowerOfTwo(col));
    return std.math.log2_int(u3, col);
}

pub fn getColumn(colNum: u3) u8 {
    return @as(u8, 1) << colNum;
}

