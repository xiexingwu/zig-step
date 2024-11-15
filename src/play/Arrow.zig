const Arrow = @This();

const std = @import("std");
const rl = @import("raylib");
const Simfile = @import("../simfile/Simfile.zig");
const screen = @import("../screen.zig");
const Play = @import("./Play.zig");
const PlayMode = @import("./PlayMode.zig");
const Judgment = @import("./Judgment.zig");
const Sounds = @import("./Sounds.zig");
const log = std.log;

note: Simfile.Note,
beat: f32, // for MMOD
time: f32, // for CMOD and judgment
time2: f32 = -1, // start of hold/roll
texture: rl.Texture,
judgment: Judgment.Kind = .nil,
judgmentOk: ?bool = null,

timeTapped: f32 = -1, // To track hold/roll progress

/// Given the notes of a simfile chart, this initialises an array of arrows
/// that can be rendered/judged during play.
pub fn init(allocator: std.mem.Allocator, spdp: PlayMode.SpDp, notes: []Simfile.Note) ![]Arrow {
    initBaseArrowImgs();

    var arrows = try allocator.alloc(Arrow, notes.len);
    for (notes, 0..) |note, i| {
        const img = genImageArrow(spdp, note, i);
        defer rl.unloadImage(img);
        const texture = rl.loadTextureFromImage(img);
        arrows[i] = .{
            .note = note,
            .beat = note.getSongBeat(),
            .time = note.time,
            .texture = texture,
        };
    }
    return arrows;
}

pub fn deinit() void {
    rl.unloadImage(baseArrowImgs.L);
    rl.unloadImage(baseArrowImgs.D);
    rl.unloadImage(baseArrowImgs.U);
    rl.unloadImage(baseArrowImgs.R);
}

const baseArrowImgs = struct {
    var L: rl.Image = undefined;
    var R: rl.Image = undefined;
    var U: rl.Image = undefined;
    var D: rl.Image = undefined;

    pub fn get(orientation: Simfile.Note.Orientation) rl.Image {
        return switch (orientation) {
            .R => baseArrowImgs.R,
            .U => baseArrowImgs.U,
            .D => baseArrowImgs.D,
            .L => baseArrowImgs.L,
        };
    }
};

fn initBaseArrowImgs() void {
    const arrPx = screen.getArrSzPx();
    var dn = rl.loadImage("./resources/down_receptor_dark_64.png");
    rl.imageResize(&dn, arrPx, arrPx);

    var lt = rl.imageCopy(dn);
    rl.imageRotate(&lt, 90);

    var up = rl.imageCopy(dn);
    rl.imageRotate(&up, 180);

    var rt = rl.imageCopy(dn);
    rl.imageRotate(&rt, -90);

    baseArrowImgs.L = lt;
    baseArrowImgs.D = dn;
    baseArrowImgs.U = up;
    baseArrowImgs.R = rt;
}

pub fn judge(self: Arrow, state: Play) ?Judgment.Kind {
    const time = rl.getMusicTimePlayed(state.music);
    var keys: u8 = 0;
    // Check P1 & P2 notes
    if (rl.isKeyPressed(.key_left)) keys |= 1;
    if (rl.isKeyPressed(.key_down)) keys |= 2;
    if (rl.isKeyPressed(.key_up)) keys |= 4;
    if (rl.isKeyPressed(.key_right)) keys |= 8;

    if (self.judgment != .nil) {
        log.err("Trying to judge an already judged note.", .{});
        unreachable;
    }
    const timing = time - self.time; // positive is late
    if (timing < -0.142) return null; // short-circuit if note is far away
    if (timing > 0.142) return .miss;

    const correct = keys == self.note.columns;

    // TODO: Make this programmatic via JudgmentTypes
    if (state.playMode.autoplay and @abs(timing) <= 0.0167) {
        if (state.playMode.assistClap and (self.note.value == .note or self.note.value == .hold)) {
            rl.playSound(Sounds.clap);
        }
        return if (self.note.value == .tail) .ok else .marvelous;
    }
    if (correct and @abs(timing) <= 0.0167) return if (self.note.value == .tail) .ok else .marvelous;
    if (correct and @abs(timing) <= 0.033) return .perfect;
    if (correct and @abs(timing) <= 0.092) return .great;
    if (correct and @abs(timing) <= 0.142) return .good;
    return null;
}

//// Internal draw/img functions
fn genImageCircleArrow() rl.Image {
    log.err("unused function", .{});
    std.debug.assert(false);
    const arrSz = screen.getArrSzPx();
    var arrow = rl.genImageColor(arrSz, arrSz, rl.Color.blank);
    const centre = @divTrunc(arrSz, 2);
    const radius = @divTrunc(arrSz, 3);
    rl.imageDrawCircle(
        &arrow,
        centre,
        centre,
        radius,
        rl.Color.white,
    );

    log.debug(
        "Base arrow size {}x{}, centred {},{}\n",
        .{ arrSz, arrSz, @divTrunc(arrSz, 2), @divTrunc(arrSz, 2) },
    );
    return arrow;
}

/// Loads a down arrow
fn genImageArrow(spdp: PlayMode.SpDp, note: Simfile.Note, arrIndex: usize) rl.Image {
    var canvas = rl.genImageColor(screen.dims.width, screen.getArrSzPx(), rl.Color.blank);

    const nCols: u4 = switch (spdp) {
        .Sp => 4,
        .Dp => 8,
    };

    for (0..nCols) |i| {
        const colNum: u3 = @intCast(i);
        if (!note.hasColumnNum(colNum)) continue;

        const arrow = baseArrowImgs.get(Simfile.Note.getOrientation(colNum));
        const xPos: f32 = @floatFromInt(Play.Lane.getArrXPx(spdp, colNum));
        const arrSz: f32 = @floatFromInt(screen.getArrSzPx());
        rl.imageDraw(
            &canvas,
            arrow,
            .{ .x = 0, .y = 0, .width = @floatFromInt(canvas.width), .height = @floatFromInt(canvas.height) },
            .{ .x = xPos, .y = 0, .width = arrSz, .height = arrSz },
            rl.Color.white,
        );

        const showDebug = @import("../main.zig").appState.showDebug;
        if (showDebug) {
            var buf: [8]u8 = undefined;
            const indexStr = std.fmt.bufPrintZ(&buf, "{d:.0}", .{arrIndex}) catch unreachable;
            const font = if (rl.isFontReady(screen.debugFont)) screen.debugFont else rl.getFontDefault();
            rl.imageDrawTextEx(&canvas, font, indexStr, .{ .x = xPos + arrSz / 2, .y = arrSz / 2 }, 24.0, 4, rl.Color.white);
        }
    }

    rl.imageColorTint(&canvas, note.getColor());

    return canvas;
}
