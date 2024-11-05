const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log;
const print = std.debug.print;

const rl = @import("raylib");

const sm = @import("./simfile.zig");
const screen = @import("./screen.zig");

const ARROW_DIMS = 0.15;

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
        if (correct and @abs(timing) <= 0.0167) return .marvelous;
        if (correct and @abs(timing) <= 0.033) return .perfect;
        if (correct and @abs(timing) <= 0.092) return .great;
        if (correct and @abs(timing) <= 0.142) return .good;
        return null;
        // log.err("Note failed to judge in existing timing windows. timing = {d: >6.2}s", .{timing});
        // unreachable;
    }
};
const LaneComponentType = enum { target };
const LaneComponent = struct {
    type: LaneComponentType,
    texture: rl.Texture,
};

const State = struct {
    allocator: Allocator,
    music: rl.Music,
    musicLength: f32,
    musicEnded: bool = false,
    chart: sm.Chart,

    // Textures
    arrows: []Arrow,
    i_nextArrow: usize = 0, // Track index of next unjudged arrow

    laneComponents: []LaneComponent,
    // Song state from last frame
    bpm: f32 = 0,
    beat: f32 = 0,
    time: f32 = 0,
};

var state: State = undefined;

/// Initialise Gameplay State
pub fn init(allocator: Allocator, music: rl.Music, chart: sm.Chart) !void {
    state = State{
        .allocator = allocator,
        .music = music,
        .musicLength = rl.getMusicTimeLength(music),
        .chart = chart,
        .arrows = try initArrows(allocator, chart.notes),
        .laneComponents = try initLaneComponents(allocator),
    };
}

fn initArrows(allocator: Allocator, notes: []sm.Note) ![]Arrow {
    var arrows = try allocator.alloc(Arrow, notes.len);
    // var buf: [16]u8 = undefined;
    var baseArrow = genBaseArrow();
    defer rl.unloadImage(baseArrow);
    for (notes, 0..) |note, i| {
        // print("note {d}, m{d: >2} b{d: >3}/{d: <3}: {c} @ {s} @ b {d: >6.2} {d: >5.2}s\n", .{
        //     i,                    note.measure,
        //     note.numerator,       note.denominator,
        //     note.getColumnChar(), @tagName(note.type),
        //     note.getSongBeat(),   note.time,
        // });
        // const str = std.fmt.bufPrintZ(&buf, "{d: >4.0}", .{i}) catch "0";
        // const baseArrow = rl.genImageText(40, 40, str);
        // defer rl.unloadImage(img);
        rl.imageColorTint(&baseArrow, note.getColor());
        const texture = rl.loadTextureFromImage(baseArrow);
        arrows[i] = .{
            .note = note,
            .beat = note.getSongBeat(),
            .time = note.time,
            .texture = texture,
        };
        // arrows[i].note = note;
        // arrows[i].beat = note.getSongBeat();
        // arrows[i].time = note.time;
        // arrows[i].texture = texture;
        // arrows[i].judgment = .nil;
        // print("arrow {d}:@ b {d: >6.2} {d: >5.2}s judged {s}\n", .{
        //     i,
        //     arrows[i].beat,
        //     arrows[i].time,
        //     @tagName(arrows[i].judgment),
        // });
    }
    return arrows;
}

fn initLaneComponents(allocator: Allocator) ![]LaneComponent {
    var i: u8 = 0;
    for (std.meta.fieldNames(LaneComponentType)) |_| {
        i += 1;
    }
    const components = try allocator.alloc(LaneComponent, i);
    for (components) |*component| {
        switch (component.type) {
            .target => {
                const sz = screen.Px.fromPt(.{ .x = 1, .y = ARROW_DIMS });
                var img = rl.genImageColor(sz.x, sz.y, rl.Color.blank);
                defer rl.unloadImage(img);

                rl.imageDrawLine(
                    &img,
                    0,
                    @divTrunc(sz.y, 2),
                    sz.x,
                    @divTrunc(sz.y, 2),
                    rl.Color.gray,
                );
                component.texture = rl.loadTextureFromImage(img);

                log.debug("lane target size {}x{}, centred {}\n", .{ sz.x, sz.y, @divTrunc(sz.y, 2) });
            },
        }
    }
    return components;
}

pub fn deinit() void {
    // arrows
    for (state.arrows) |arrow| {
        rl.unloadTexture(arrow.texture);
    }
    // lane components
    for (state.laneComponents) |component| {
        rl.unloadTexture(component.texture);
    }
}

/// Check the song has ended
pub fn hasSongEnded() bool {
    const timePlayed = rl.getMusicTimePlayed(state.music);
    // Dirty hack to check song finished the first time and prevent it
    // from looping. timePlayed cannot line up with musicLength
    // exactly, hence cull it at the beginning of the loop.
    if (timePlayed >= 0.99 * state.musicLength) state.musicEnded = true;
    if (state.musicEnded) return timePlayed < 5 or timePlayed > state.musicLength;
    return false;
}

/// Given current beat # of song and velocity of notes, converts a beat to
/// distance to the step target.
pub fn beat2Distance(beat: f32, velocity: f32) f32 {
    const DIST_PER_BEAT = 0.1315;
    return velocity * beat * DIST_PER_BEAT;
}

/// Determines the current beat # of the song
pub fn updateBeat(time: f32) void {
    const dt = time - state.time;
    const beat = state.beat + sm.timeToBeat(dt, state.bpm);

    // Split beat if gimmick appeared between last beast and now.
    const bpms = state.chart.bpms;
    const gimm = bpms[0];
    assert(gimm.type == .bpm);
    if (gimm.beat > state.beat and gimm.beat < beat) {
        updateBeat(gimm.time);
        state.bpm = gimm.value;
        state.chart.bpms = state.chart.bpms[1..];
    }
}

pub fn judgeArrows() void {
    const i = &state.i_nextArrow;
    const arrows = state.arrows;
    const time = rl.getMusicTimePlayed(state.music);
    print("{}/{}\n", .{ i.*, arrows.len });
    while (i.* < arrows.len) {
        var arrow = &arrows[i.*];
        if (arrow.judge(time)) |judgment| {
            arrow.judgment = judgment;
            log.debug("arrow {d} @ b{d: >6.2}, {d: >6.2}s @ {d: >6.2}s judged {s}", .{ i, arrow.beat, arrow.time, time, @tagName(judgment) });
            rl.unloadTexture(arrow.texture);
            i.* += 1;
        } else {
            break;
        }
    }
    // for (arrows) |*arrow| {
    //     // log.debug("pre-judge: arrow {d} @ b{d: >6.2}, {d: >6.2}s @ {d: >6.2}s judged {s}", .{ i, arrow.beat, arrow.time, time, @tagName(arrow.judgment) });
    //     if (arrow.judge(time)) |judgment| {
    //         arrow.judgment = judgment;
    //         log.debug("arrow {d} @ b{d: >6.2}, {d: >6.2}s @ {d: >6.2}s judged {s}", .{ i, arrow.beat, arrow.time, time, @tagName(judgment) });
    //         state.arrows = arrows[i + 1 ..];
    //     } else {
    //         break;
    //     }
    // }
}

//// DRAW functions
pub fn drawLane() void {
    const TARGET_OFFSET = 0.162 - ARROW_DIMS / 2.0;
    for (state.laneComponents) |component| {
        switch (component.type) {
            .target => {
                const pos = (screen.Pt{ .x = 0, .y = TARGET_OFFSET }).toPx();
                rl.drawTexture(component.texture, pos.x, pos.y, rl.Color.white);
            },
        }
    }
}

fn drawArrow(note: sm.Note) void {
    _ = note;
}

pub fn drawArrows() void {
    const arrows = state.arrows[state.i_nextArrow..];
    for (arrows, 0..) |note, i| {
        assert(note.judgment == .nil);
        if (note.judgment != .nil) {
            state.chart.notes = state.chart.notes[i + 1 ..];
            rl.unloadTexture();
            continue;
        }
        drawArrow(note);
    }
}

pub fn drawTimePlayedMsg() void {
    const timePlayed = rl.getMusicTimePlayed(state.music);
    var buf: [32]u8 = undefined;
    const msg = std.fmt.bufPrintZ(
        &buf,
        "{d:0>2.0}:{d:0>2.0}.{d:0>2.0}",
        .{
            @divTrunc(timePlayed, 60),
            @rem(timePlayed, 60),
            @rem(timePlayed, 1) * 100,
        },
    ) catch "00:00";
    rl.drawText(msg, rl.getScreenWidth() - 60, 10, 14, rl.Color.white);
}

//// Internal draw/img functions
fn genBaseArrow() rl.Image {
    const sz = screen.Px.fromPt(.{ .x = 0, .y = ARROW_DIMS }).y;
    var arrow = rl.genImageColor(sz, sz, rl.Color.white);
    rl.imageDrawCircle(
        &arrow,
        @divTrunc(sz, 2),
        @divTrunc(sz, 2),
        @divTrunc(sz, 2),
        rl.Color.white,
    );

    log.debug(
        "Base arrow size {}x{}, centred {},{}\n",
        .{ sz, sz, @divTrunc(sz, 2), @divTrunc(sz, 2) },
    );
    return arrow;
}

/// Apply alpha to arrow for CONSTANT
fn applyNoteConstantAlpha(note: *rl.Image, alpha: u32) *rl.Image {
    const mask = rl.genImageColor(note.width, note.height, rl.Color(0, 0, 0, alpha));
    return rl.imageAlphaMask(note, mask);
}
