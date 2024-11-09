const Simfile = @This();

const std = @import("std");
const rl = @import("raylib");
const parse = @import("./parse.zig");
const time = @import("./time.zig");
const play = @import("../play/Play.zig");
const log = std.log;

pub const Chart = @import("./Chart.zig");
pub const Note = @import("./Note.zig");
pub const Gimmick = @import("./Gimmick.zig");

title: [128]u8,
artist: [128]u8,
chart: *Chart,


pub fn fromFile(allocator: std.mem.Allocator, filename: []const u8, playMode: *play.PlayMode) !*Simfile {
    var simfile = try allocator.create(Simfile);
    simfile.chart = try Chart.new(allocator, playMode);

    simfile = try parse.parse(filename, simfile);

    simfile.chart = try time.timeAlloc(allocator, simfile.chart);

    log.debug("---------------", .{});
    log.debug("Title:{s}", .{simfile.title});
    log.debug("Sp/Dp:{s}", .{simfile.chart.spdp.toSmString()});
    log.debug("Diff:{s}", .{simfile.chart.diff.toSmString()});
    log.debug("Level:{d}", .{simfile.chart.level});
    log.debug("Measures:{d}", .{simfile.chart.measures});
    log.debug("Gimmicks:{d}", .{simfile.chart.gimms.len});
    log.debug("Bpms:{d}", .{simfile.chart.bpms.len});
    log.debug("Stops:{d}", .{simfile.chart.stops.len});
    Simfile.Note.summariseNotes(simfile.chart.notes);
    log.debug("---------------", .{});
    return simfile;
}
