const std = @import("std");
const rl = @import("raylib");
const sm = @import("./simfile.zig");
const log = std.log;
const print = std.debug.print;

const State = struct {
    music: rl.Music,
    musicLength: f32,
    chart: sm.Chart,
};
var state: *allowzero State = @ptrFromInt(0);

var timePlayedMsg: [32:0]u8 = undefined;

/// Initialise Gameplay State
pub fn init(allocator: std.mem.Allocator, music: rl.Music, chart: sm.Chart) !void {
    state = try allocator.create(State);
    state.music = music;
    state.musicLength = rl.getMusicTimeLength(music);
    state.chart = chart;
}

/// Check the song has ended
pub fn hasSongEnded() bool {
    const timePlayed = rl.getMusicTimePlayed(state.music);
    // Dirty hack to check song finished the first time and prevent it
    // from looping. timePlayed cannot line up with musicLength
    // exactly, hence cull it at the beginning of the loop.
    if (timePlayed >= 0.99 * state.musicLength and timePlayed < 5) return true;
    return false;
}

pub fn getTimePlayedMsg() [:0]u8 {
    const timePlayed = rl.getMusicTimePlayed(state.music);
    return std.fmt.bufPrintZ(&timePlayedMsg, "{d:0>2.0}:{d:0>2.0}.{d:0>2.0}", .{
        @divTrunc(timePlayed, 60),
        @rem(timePlayed, 60),
        @rem(timePlayed, 1) * 100,
    }) catch &timePlayedMsg;
}
