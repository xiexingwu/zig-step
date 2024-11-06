const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log;
const print = std.debug.print;

const rl = @import("raylib");

const sm = @import("./simfile.zig");
const screen = @import("./screen.zig");
const utils = @import("./utils.zig");

const ARR_LNG = 0.15; // Side length of arrow, normalised by lane height
var ARR_LNG_PX: i32 = undefined;
const TARGET_OFFSET = 0.162 - ARR_LNG / 2.0;

const Arrow = struct {
    note: sm.Note,
    beat: f32, // for MMOD
    time: f32, // for CMOD and judgment
    texture: rl.Texture,

    judgment: Judgment = .nil,

    const JudgmentTypes = struct {
        nil: f32,
        marvelous: f32 = 0.0167,
        perfect: f32 = 0.033,
        great: f32 = 0.092,
        good: f32 = 0.142,
        ok: f32,
        miss: f32,
    };
    const Judgment = std.meta.FieldEnum(JudgmentTypes);

    pub fn drawArrow(self: Arrow) void {
        const time = rl.getMusicTimePlayed(state.music);

        // Determine draw location
        const distance = beatToDist(self.beat - state.beat, state.playMode.modValue);
        if (TARGET_OFFSET + distance > 1) return;

        const yPos = screen.toPx(TARGET_OFFSET + distance);

        // Apply CONSTANT fade
        const UNFADE_TIME = 0.2; // Time (s) to unfade the arrow
        var tint = rl.Color.white;
        if (state.playMode.constant) |constant| {
            const timeUntil = self.time - time;
            var constAlpha = (constant / 1000.0 - timeUntil) / UNFADE_TIME;
            constAlpha = @max(0, @min(1, constAlpha));
            tint = rl.fade(tint, constAlpha);
        }

        // rl.drawTexture(self.texture, xPos, yPos, tint);
        rl.drawTexture(self.texture, 0, yPos, tint);
    }

    pub fn judge(self: Arrow, time: f32) ?Judgment {
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

        const correct = keys == self.note.column;

        // TODO: Make this programmatic via JudgmentTypes
        if (state.playMode.autoplay and @abs(timing) <= 0.0167) {
            if (state.playMode.assistClap) {
                rl.playSound(clap);
            }
            return .marvelous;
        }
        if (correct and @abs(timing) <= 0.0167) return .marvelous;
        if (correct and @abs(timing) <= 0.033) return .perfect;
        if (correct and @abs(timing) <= 0.092) return .great;
        if (correct and @abs(timing) <= 0.142) return .good;
        return null;
        // log.err("Note failed to judge in existing timing windows. timing = {d: >6.2}s", .{timing});
        // unreachable;
    }
};

const State = struct {
    allocator: Allocator,

    music: rl.Music,
    musicLength: f32,
    musicEnded: bool = false,

    playMode: *sm.PlayMode,

    simfile: *sm.Simfile,

    // Textures
    arrows: []Arrow,

    // Track indices
    i_nextArrow: usize = 0, // Next unjudged arrow
    i_nextGimm: usize = 0, // Next gimmick

    // Song state from last frame
    bpm: f32 = 0,
    beat: f32 = 0,
    time: f32 = 0,
};

var state: State = undefined;

var clap: rl.Sound = undefined;
const baseArrowImgs = struct {
    var L: rl.Image = undefined;
    var R: rl.Image = undefined;
    var U: rl.Image = undefined;
    var D: rl.Image = undefined;

    pub fn get(col: u3) rl.Image {
        return switch (col) {
            0, 4 => baseArrowImgs.R,
            1, 5 => baseArrowImgs.U,
            2, 6 => baseArrowImgs.D,
            3, 7 => baseArrowImgs.L,
        };
    }
};

var laneTexture: rl.Texture = undefined;

/// Initialise Gameplay State
pub fn init(allocator: Allocator, music: rl.Music, simfile: *sm.Simfile, playMode: *sm.PlayMode) !void {
    clap = rl.loadSound("./resources/clap.ogg");
    initBaseArrowImgs();
    initLane();

    state = State{
        .allocator = allocator,

        .music = music,
        .musicLength = rl.getMusicTimeLength(music),

        .simfile = simfile,
        .playMode = playMode,

        .arrows = try initArrows(allocator, simfile.chart.notes),
    };
}

fn initBaseArrowImgs() void {
    ARR_LNG_PX = screen.toPx(ARR_LNG);
    var dn = rl.loadImage("./resources/down_receptor_dark_64.png");
    rl.imageResize(&dn, ARR_LNG_PX, ARR_LNG_PX);

    var lt = rl.imageCopy(dn);
    rl.imageRotate(&lt, 90);

    var up = rl.imageCopy(dn);
    rl.imageRotate(&up, 180);

    var rt = rl.imageCopy(dn);
    rl.imageRotate(&rt, -90);

    // baseArrowImgs = .{
    baseArrowImgs.L = lt;
    baseArrowImgs.D = dn;
    baseArrowImgs.U = up;
    baseArrowImgs.R = rt;
    // };
}

fn deinitBaseArrowImgs() void {
    rl.unloadImage(baseArrowImgs.L);
    rl.unloadImage(baseArrowImgs.D);
    rl.unloadImage(baseArrowImgs.U);
    rl.unloadImage(baseArrowImgs.R);
}

fn initArrows(allocator: Allocator, notes: []sm.Note) ![]Arrow {
    var arrows = try allocator.alloc(Arrow, notes.len);
    for (notes, 0..) |note, i| {
        const img = genImageArrow(note);
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

fn initLane() void {
    const sz = screen.Px.fromPt(.{ .x = 1, .y = ARR_LNG });
    var canvas = rl.genImageColor(sz.x, sz.y, rl.Color.blank);
    defer rl.unloadImage(canvas);

    rl.imageDrawLine(&canvas, 0, @divTrunc(sz.y, 2), sz.x, @divTrunc(sz.y, 2), rl.Color.gray);

    for (0..4) |i| {
        const col: u3 = @intCast(i);
        const arrow = baseArrowImgs.get(col);

        const xPos = (3 - col) * sz.y;
        rl.imageDraw(
            &canvas,
            arrow,
            .{ .x = 0, .y = 0, .width = @floatFromInt(canvas.width), .height = @floatFromInt(canvas.height) },
            .{ .x = @floatFromInt(xPos), .y = 0, .width = @floatFromInt(sz.y), .height = @floatFromInt(sz.y) },
            rl.Color.white,
        );
    }

    laneTexture = rl.loadTextureFromImage(canvas);

    log.debug("lane target size {}x{}, centred {}\n", .{ sz.x, sz.y, @divTrunc(sz.y, 2) });
}

pub fn deinit() void {
    rl.unloadTexture(laneTexture);
    rl.unloadSound(clap);
    deinitBaseArrowImgs();
    // arrows
    for (state.arrows) |arrow| {
        rl.unloadTexture(arrow.texture);
    }
}

/// Check the song has ended
pub fn hasSongEnded() bool {
    const time = rl.getMusicTimePlayed(state.music);
    // Dirty hack to check song finished the first time and prevent it
    // from looping. timePlayed cannot line up with musicLength
    // exactly, hence cull it at the beginning of the loop.
    if (time >= 0.99 * state.musicLength) state.musicEnded = true;
    if (state.musicEnded) return time < 5 or time > state.musicLength;
    return false;
}

/// Given current beat # of song and velocity of notes, converts a beat to
/// distance to the step target.
pub fn beatToDist(beat: f32, mmod: f32) f32 {
    const DIST_PER_BEAT = 0.1315;
    return mmod * beat * DIST_PER_BEAT;
}

/// Determines the current beat # of the song
pub fn updateBeat() void {
    const time = rl.getMusicTimePlayed(state.music);

    const dt = time - state.time;
    var db = utils.timeToBeat(dt, state.bpm);
    // print("time {d:.3}->{d:.3}s beat: {d:.2}\n", .{ state.time, time, state.beat });

    // Split beat if bpm gimmick appeared between last beast and now.
    const gimms = state.simfile.summary.gimms;

    const i = &state.i_nextGimm;
    while (i.* < gimms.len) : (i.* += 1) {
        const gimm = gimms[i.*];
        if (gimm.time > time) break; // don't need to deal with this gimmick yet

        // Initialise song bpm
        if (i.* == 0) {
            assert(gimm.type == .bpm and gimm.beat == 0.0);
            state.bpm = gimm.value;
            log.debug("set BPM {d:.2}", .{state.bpm});
            continue;
        }

        switch (gimm.type) {
            // Pause beating until song catches up to end of stop
            .stop => {
                if (time < gimm.time + gimm.value) {
                    db = 0;
                    break;
                }
            },

            // Update bpm (split beat if necessary)
            .bpm => {
                // const dt1 = gimm.time - state.time;
                const dt2 = time - gimm.time;
                db -= utils.timeToBeat(dt2, state.bpm);
                db += utils.timeToBeat(dt2, gimm.value);

                state.bpm = gimm.value;
                continue;
            },
            .nil => {
                log.err("Found unitialized gimmick when updating beaet.", .{});
                unreachable;
            },
        }
    }

    state.time = time;
    state.beat += db;
}

pub fn judgeArrows() void {
    const i = &state.i_nextArrow;
    const arrows = state.arrows;
    const time = rl.getMusicTimePlayed(state.music);
    while (i.* < arrows.len) {
        var arrow = &arrows[i.*];
        if (arrow.judge(time)) |judgment| {
            arrow.judgment = judgment;
            log.debug(
                "arrow {d} @ b{d: >6.2}, {d: >6.2}s @ {d: >6.2}s judged {s}",
                .{ i.*, arrow.beat, arrow.time, time, @tagName(judgment) },
            );
            rl.unloadTexture(arrow.texture);
            i.* += 1;
        } else {
            break;
        }
    }
}

//// DRAW functions
pub fn drawLane() void {
    const pos = (screen.Pt{ .x = 0, .y = TARGET_OFFSET }).toPx();
    rl.drawTexture(laneTexture, pos.x, pos.y, rl.Color.white);
}

pub fn drawArrows() void {
    const arrows = state.arrows[state.i_nextArrow..];
    for (arrows) |arrow| {
        assert(arrow.judgment == .nil);
        arrow.drawArrow();
    }
}

pub fn drawTimePlayedMsg() void {
    const time = rl.getMusicTimePlayed(state.music);
    var buf: [32]u8 = undefined;
    const msg = std.fmt.bufPrintZ(
        &buf,
        "{d:0>2.0}:{d:0>2.0}.{d:0>2.0}",
        .{
            @divTrunc(time, 60),
            @rem(time, 60),
            @rem(time, 1) * 100,
        },
    ) catch "00:00";
    rl.drawText(msg, rl.getScreenWidth() - 60, 10, 14, rl.Color.white);
}

//// Internal draw/img functions
fn genImageCircleArrow() rl.Image {
    var arrow = rl.genImageColor(ARR_LNG_PX, ARR_LNG_PX, rl.Color.blank);
    const centre = @divTrunc(ARR_LNG_PX, 2);
    const radius = @divTrunc(ARR_LNG_PX, 3);
    rl.imageDrawCircle(
        &arrow,
        centre,
        centre,
        radius,
        rl.Color.white,
    );

    log.debug(
        "Base arrow size {}x{}, centred {},{}\n",
        .{ ARR_LNG_PX, ARR_LNG_PX, @divTrunc(ARR_LNG_PX, 2), @divTrunc(ARR_LNG_PX, 2) },
    );
    return arrow;
}

/// Loads a down arrow
fn genImageArrow(note: sm.Note) rl.Image {
    var canvas = rl.genImageColor(screen.dims.width, ARR_LNG_PX, rl.Color.blank);

    for (0..4) |i| {
        const col: u3 = @intCast(i);
        if (note.column & @as(u8, 1) << (3 - col) == 0) {
            continue;
        }

        const baseArrow = baseArrowImgs.get(col);

        const xPos = (3 - col) * ARR_LNG_PX;
        rl.imageDraw(
            &canvas,
            baseArrow,
            .{ .x = 0, .y = 0, .width = @floatFromInt(canvas.width), .height = @floatFromInt(canvas.height) },
            .{ .x = @floatFromInt(xPos), .y = 0, .width = @floatFromInt(ARR_LNG_PX), .height = @floatFromInt(ARR_LNG_PX) },
            rl.Color.white,
        );
    }

    rl.imageColorTint(&canvas, note.getColor());
    return canvas;
}
