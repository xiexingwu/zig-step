const Note = @This();
pub const Note0 = Note{}; // Sentinel

const std = @import("std");
const rl = @import("raylib");
const Simfile = @import("./Simfile.zig");
const log = std.log;

pub const Value = enum(u8) {
    sentinel = '0',
    note,
    hold,
    tail,
    roll,
    mine = 'M',
    fake = 'F',
    pseudoHold = 'H', // Jump with at least one arrow as a hold/roll
};

pub const Orientation = enum(u8) {
    L = 'L',
    R = 'R',
    D = 'D',
    U = 'U',
};

value: Value = .sentinel,

// bit-wise indication of active columns
// For SP: only the 4 LSBs are used, with MSB being left, LSB being right
// For DP: MSB is p1-left, LSB is p2-right
columns: u8 = 0,

denominator: u16 = 0, // # of lines measure is broken into: 4 = quarter notes, 8 = eighth notes etc.
numerator: u16 = 0, // line of appearance (0-indexed)
measure: u16 = 0, // measure (0-indexed)
time: f32 = 0, // arrival time (sec)
time2: f32 = 0, // alternate time field, e.g. start of hold/roll

//// Methods

pub fn isJump(self: Note) bool {
    return !std.math.isPowerOfTwo(self.columns);
}

pub fn hasColumnNum(self: Note, colNum: u3) bool {
    return self.columns & getColumnBits(colNum) > 0;
}

pub fn getColumnStr(self: Note) [8]u8 {
    var buf: [8]u8 = undefined;
    for (0..8) |i| {
        const colNum: u3 = @intCast(7 - i);
        buf[i] = if (self.hasColumnNum(colNum)) Note.getOrientationChar(colNum) else ' ';
    }
    return buf;
}

pub fn getValueStr(self: Note) [8]u8 {
    var buf: [8]u8 = undefined;
    for (0..8) |i| {
        const colNum: u3 = @intCast(7 - i);
        buf[i] = if (self.hasColumnNum(colNum)) Note.getValueChar(self.value) else ' ';
    }
    return buf;
}

pub fn getDebugStr(self: Note) [:0]u8 {
    var buf: [18]u8 = undefined;
    return std.fmt.bufPrintZ(&buf, "{s}\n{s}", .{ self.getColumnStr(), self.getValueStr() }) catch unreachable;
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
    switch (self.value) {
        .roll, .mine, .fake => return rl.Color.blank,
        .tail => return rl.Color.gray,
        .hold => return rl.Color.dark_green,
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

//// Type functions

pub fn lessThan(_: @TypeOf(.{}), lhs: Note, rhs: Note) bool {
    // Sentinel should settle to the end
    if (lhs.value == .sentinel) return false;
    if (rhs.value == .sentinel) return true;
    if (lhs.getSongBeat() < rhs.getSongBeat()) return true;
    return false;
}

pub fn getColumnNum(column: u8) u3 {
    std.debug.assert(std.math.isPowerOfTwo(column));
    return @intCast(std.math.log2_int(u8, column));
}

pub fn getOrientation(colNum: u3) Orientation {
    return switch (colNum) {
        0, 4 => .R,
        1, 5 => .U,
        2, 6 => .D,
        3, 7 => .L,
    };
}

pub fn getColumnBits(colNum: u3) u8 {
    return @as(u8, 1) << colNum;
}

pub fn getOrientationChar(colNum: u3) u8 {
    const char = @tagName(getOrientation(colNum))[0];
    return if (colNum >= 4) std.ascii.toLower(char) else char;
}

pub fn getValueChar(value: Note.Value) u8 {
    return @tagName(value)[0];
}
/// Jumps (two simulations notes) are considered one note.
/// Freeze tails are considered one note iff the corresponding holds started as one note.
/// Jumps where only one foot is a freeze will become type=pseudo-hold so it can appear green
/// TODO: Assuming all 8 notes can be active, there's a maximum of 4 simultaneous pairs of freeze/releases.
///     Currently only tracks one pair of freezes.
pub fn mergeSimultaneousNotes(notes: []Simfile.Note) []Simfile.Note {
    var freezeCols: u8 = 0; // Track freeze columns triggered simulatneously

    var i: u16 = 0;
    var merged: u16 = 0;
    while (i < notes.len - 1) : (i += 1) {
        var n1 = &notes[i];
        var n2 = &notes[i + 1];
        if (n1.getSongBeat() != n2.getSongBeat()) continue; // Not simultaneous
        if (n1.value == .sentinel) unreachable; // Already processed

        // Check for psuedo hold
        const canN1Pseudo = n1.value == .note or n1.value == .hold or n1.value == .roll;
        const canN2Pseudo = n2.value == .note or n2.value == .hold or n2.value == .roll;
        if (!(canN1Pseudo and canN2Pseudo) and n1.value != n2.value) continue; // Notes of differen type can't merge

        const columns = n2.columns | n1.columns; // Merge columns

        if (n1.value == n2.value) {
            switch (n1.value) {
                .note => {},
                .hold, .roll => freezeCols = columns, // mark frozen columns
                .tail => {
                    if (columns != freezeCols) {
                        freezeCols = 0;
                        continue;
                    }
                }, // only merge if they started together
                .mine => {},
                else => continue,
            }
        } else {
            n2.value = .pseudoHold;
        }

        log.debug(
            "Merging {}:{}, meas {} {}/{}, beat {d:.2}:{d:.2}, type {s}:{s}",
            .{ i, i + 1, n1.measure, n1.numerator, n1.denominator, n1.getSongBeat(), n2.getSongBeat(), @tagName(n1.value), @tagName(n2.value),  },
        );
        n1.* = Simfile.Note.Note0;
        n2.columns = columns;
        merged += 1;
    }

    std.sort.pdq(Simfile.Note, notes, .{}, Simfile.Note.lessThan);
    log.debug("Notes {} initially {} merged", .{ notes.len, merged });
    return notes[0 .. notes.len - merged];
}

pub fn summariseNotes(notes: []Note) void {
    var iNote: u16 = 0;
    var iJump: u16 = 0;
    var iOk: u16 = 0;
    for (notes, 0..) |note, i| {
        switch (note.value) {
            .note, .hold, .pseudoHold => {
                iNote += 1;
                iJump += if (note.isJump()) 1 else 0;
            },
            .tail, .mine => {
                iOk += 1;
            },
            else => {
                log.err("Note {}: {s} @ meas {} {}/{}", .{ i, @tagName(note.value), note.measure, note.numerator, note.denominator });
                unreachable;
            },
        }
    }
    log.debug("Notes:{}", .{notes.len});
    log.debug("\t{d: >4} steps ({} jump)", .{ iNote, iJump });
    log.debug("\t{d: >4} OK", .{iOk});
}
