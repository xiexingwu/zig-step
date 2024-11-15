const Play = @This();
pub var state: Play = undefined;

const std = @import("std");
const rl = @import("raylib");
const Simfile = @import("../simfile/Simfile.zig");
const screen = @import("../screen.zig");
const utils = @import("../utils/utils.zig");
const log = std.log;

pub const PlayMode = @import("./PlayMode.zig");
pub const Arrow = @import("./Arrow.zig");
pub const Lane = @import("./Lane.zig");

// State of current song
allocator: std.mem.Allocator,

music: rl.Music,
musicLength: f32,
musicEnded: bool = false,
musicPaused: bool = false,

playMode: *PlayMode,

simfile: *Simfile,

// Textures
arrows: []Arrow,

// Track indices
// TODO: refactor to allow song seeking
i_nextArrow: usize = 0, // Next unjudged arrow
i_nextGimm: usize = 0, // Next gimmick

// Song state from last frame
bpm: f32 = 0,
beat: f32 = 0,
time: f32 = 0,

notesTap: u16 = 0,
notesMiss: u16 = 0,
notesOk: u16 = 0,

var laneTexture: rl.Texture = undefined;

/// Initialise Gameplay State
pub fn init(allocator: std.mem.Allocator, music: rl.Music, simfile: *Simfile, playMode: *PlayMode) !void {
    state = Play{
        .allocator = allocator,

        .music = music,
        .musicLength = rl.getMusicTimeLength(music),

        .simfile = simfile,
        .playMode = playMode,

        .arrows = try Arrow.init(allocator, playMode.spdp, simfile.chart.notes),
    };
    Lane.init(playMode.spdp);
}

pub fn deinit() void {
    rl.unloadTexture(laneTexture);
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

/// Determines the current beat # of the song
pub fn updateBeat() void {
    if (rl.isKeyPressed(.key_space)) {
        state.musicPaused = !state.musicPaused;
        switch (state.musicPaused) {
            true => rl.pauseMusicStream(state.music),
            false => rl.resumeMusicStream(state.music),
        }
    }
    if (state.musicPaused) return;

    const time = rl.getMusicTimePlayed(state.music);

    const dt = time - state.time;
    var db = utils.timeToBeat(dt, state.bpm);

    // Split beat if bpm gimmick appeared between last beast and now.
    const gimms = state.simfile.chart.gimms;

    const i = &state.i_nextGimm;
    while (i.* < gimms.len) : (i.* += 1) {
        const gimm = gimms[i.*];
        if (gimm.time > time) break; // don't need to deal with this gimmick yet

        // Initialise song bpm
        if (i.* == 0) {
            std.debug.assert(gimm.type == .bpm and gimm.beat == 0.0);
            state.bpm = gimm.value;
            log.debug("set BPM {d:.2}", .{state.bpm});
            continue;
        }

        // print("time {d:.3}->{d:.3}s beat: {d:.2}\n", .{ state.time, time, state.beat });
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
        if (arrow.judge(state)) |judgment| {
            switch (judgment) {
                .miss => state.notesMiss += 1,
                .ok => state.notesOk += 1,
                else => state.notesTap += 1,
            }
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

pub fn drawTimePlayedMsg() void {
    // const time = rl.getMusicTimePlayed(state.music);
    const time = state.time;
    var buf: [32]u8 = undefined;
    const msg = std.fmt.bufPrintZ(
        &buf,
        "{d:0>2.0}:{d:0>2.0}.{d:0>2.0}\n{d:.0}",
        .{
            @divTrunc(time, 60),
            @rem(time, 60),
            @rem(time, 1) * 100,
            state.bpm,
        },
    ) catch "00:00";
    rl.drawText(msg, rl.getScreenWidth() - 60, 10, 14, rl.Color.white);
}
