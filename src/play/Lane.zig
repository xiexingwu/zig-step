const Lane = @This();

const std = @import("std");
const rl = @import("raylib");
const Simfile = @import("../simfile/Simfile.zig");
const Play = @import("./Play.zig");
const Arrow = @import("./Arrow.zig");
const screen = @import("../screen.zig");
const log = std.log;

var laneTexture: rl.Texture = undefined;

const TARGET_OFFSET_X = 0.025; // 2.5% margin
const TARGET_OFFSET_Y = 0.162 - screen.ARR_LNG / 2.0; // bottom of receptor lines up to 0.162

pub fn init(spdp: Play.PlayMode.SpDp) void {
    laneTexture = loadReceptorTexture(spdp);
}

pub fn deinit() void {
    rl.unloadTexture(laneTexture);
}

pub fn draw(state: Play) void {
    const pos = screen.Px.fromPt(.{ .x = TARGET_OFFSET_X, .y = TARGET_OFFSET_Y });

    rl.drawTexture(laneTexture, pos.x, pos.y, rl.Color.white);
    // drawGuides(state); // missing implementation
    drawArrows(state);

    drawStats(state);
}

fn loadReceptorTexture(spdp: Play.PlayMode.SpDp) rl.Texture {
    const recSz = screen.Px.fromPt(.{ .x = 1, .y = screen.ARR_LNG });
    var canvas = rl.genImageColor(recSz.x, recSz.y, rl.Color.blank);
    defer rl.unloadImage(canvas);

    var dn = loadReceptorDownImage();
    rl.imageResize(&dn, screen.getArrSzPx(), screen.getArrSzPx());
    defer rl.unloadImage(dn);

    var lt = rl.imageCopy(dn);
    var up = rl.imageCopy(dn);
    var rt = rl.imageCopy(dn);
    defer rl.unloadImage(lt);
    defer rl.unloadImage(up);
    defer rl.unloadImage(rt);

    rl.imageRotate(&lt, 90);
    rl.imageRotate(&up, 180);
    rl.imageRotate(&rt, -90);

    // rl.imageDrawLine(&canvas, 0, @divTrunc(recSz.y, 2), recSz.x, @divTrunc(recSz.y, 2), rl.Color.gray);
    const canvasRect: rl.Rectangle = .{ .x = 0, .y = 0, .width = @floatFromInt(canvas.width), .height = @floatFromInt(canvas.height) };
    const nCols: u4 = switch (spdp) {
        .Sp => 4,
        .Dp => 8,
    };
    for (0..nCols) |i| {
        const col: u3 = @intCast(i);
        const rec = switch (Simfile.Note.getOrientation(col)) {
            .D => dn,
            .U => up,
            .R => rt,
            .L => lt,
        };
        const xPos: f32 = @floatFromInt(getArrXPx(spdp, col));
        const ySz: f32 = @floatFromInt(recSz.y);
        const arrowRect: rl.Rectangle = .{ .x = xPos, .y = 0, .width = ySz, .height = ySz };
        rl.imageDraw(&canvas, rec, canvasRect, arrowRect, rl.Color.white);
    }

    log.debug("lane target size {}x{}, centred {}\n", .{ recSz.x, recSz.y, @divTrunc(recSz.y, 2) });
    return rl.loadTextureFromImage(canvas);
}

fn loadReceptorDownImage() rl.Image {
    return rl.loadImage("./resources/down_receptor_dark_64.png");
}

fn drawArrows(state: Play) void {
    const arrows = state.arrows[state.i_nextArrow..];
    for (arrows) |arrow| {
        std.debug.assert(arrow.judgment == .nil);
        const time = rl.getMusicTimePlayed(state.music);

        // Determine draw location
        const distance = beatToDist(arrow.beat - state.beat, state.playMode.modValue);
        if (TARGET_OFFSET_Y + distance > 1) return;

        const yPos = screen.toPx(TARGET_OFFSET_Y + distance);

        // Apply CONSTANT fade
        const UNFADE_TIME = 0.2; // Time (s) to unfade the arrow
        var tint = rl.Color.white;
        if (state.playMode.constant) |constant| {
            const timeUntil = arrow.time - time;
            var constAlpha = (constant / 1000.0 - timeUntil) / UNFADE_TIME;
            constAlpha = @max(0, @min(1, constAlpha));
            tint = rl.fade(tint, constAlpha);
        }

        rl.drawTexture(arrow.texture, 0, yPos, tint);

        // const showDebug = @import("../main.zig").appState.showDebug;
        // if (showDebug) {
        //     const font = if (rl.isFontReady(screen.debugFont)) screen.debugFont else rl.getFontDefault();
        //     const debugStr = arrow.note.getDebugStr()[0..17 :0];
        //     rl.drawTextEx(font, debugStr, .{ .x = 0, .y = @floatFromInt(yPos) }, 24.0, 4, rl.Color.white);
        // }
    }
}

/// Given current beat # of song and velocity of notes, converts a beat to
/// normalised distance to the step target.
fn beatToDist(beat: f32, mmod: f32) f32 {
    const DIST_PER_BEAT = 0.1315;
    return mmod * beat * DIST_PER_BEAT;
}

/// Given column (0 = right-most, 7 = left-most),
/// determine horizontal pixel offset from left-edge of lane.
pub fn getArrXPx(spdp: Play.PlayMode.SpDp, col: u3) i32 {
    const nCols: u4 = switch (spdp) {
        .Sp => 4,
        .Dp => 8,
    };
    return (nCols - 1 - col) * screen.getArrSzPx();
}

fn drawStats(state: Play) void {
    var buf: [64]u8 = undefined;
    const stats = std.fmt.bufPrintZ(
        &buf,
        "Hit :{d: >3}\nMiss:{d: >3}\nOK  :{d: >3}",
        .{ state.notesTap, state.notesMiss, state.notesOk },
    ) catch "";
    const pos = screen.Px.fromPt(.{ .x = 0.7, .y = 0.8 });
    const font = if (rl.isFontReady(screen.debugFont)) screen.debugFont else rl.getFontDefault();
    rl.drawTextEx(font, stats, .{ .x = @floatFromInt(pos.x), .y = @floatFromInt(pos.y) }, 24.0, 4, rl.Color.white);
}
