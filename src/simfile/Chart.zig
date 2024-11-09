const Chart = @This();

const std = @import("std");
const log = std.log;

const Simfile = @import("./simfile.zig");
const Play = @import("../play/Play.zig");
const Note = Simfile.Note;
const Gimmick = Simfile.Gimmick;

const MAX_NOTES = 1024; // MAX360 CSP is 1000
const MAX_BPMS = 512; // DeltaMAX is 473
const MAX_STOPS = 128; // Chaos TTM is 70(?)

spdp: Play.PlayMode.SpDp,
diff: Play.PlayMode.Diff,
level: u8 = 0,

bpms: []Gimmick,
stops: []Gimmick,
gimms: []Gimmick,
offset: f32,

measures: u8,

notes: []Note,

pub fn new(allocator: std.mem.Allocator, playMode: *Play.PlayMode) !*Chart {
    var chart = try allocator.create(Chart);
    chart.bpms = try allocator.alloc(Gimmick, MAX_BPMS);
    chart.stops = try allocator.alloc(Gimmick, MAX_STOPS);
    chart.notes = try allocator.alloc(Note, MAX_NOTES);

    chart.spdp = playMode.spdp;
    chart.diff = playMode.diff;
    return chart;
}

