const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const MAX_GUIDES = 4 * 256; // Is 256 measures for ddr songs?
const MAX_NOTES = 1024; // MAX360 CSP is 1000
const MAX_SIMFILE_BYTES = 256 * 1024; // At time of writing, largest DDR simfile is Fascination MAXX @ 137kB
const MAX_BPMS = 512; // DeltaMAX is 473
const MAX_STOPS = 128; // Chaos TTM is 70(?)

//// Types
pub const Mod = enum {
    mmod,
    constant,
    cmod,
};

pub const PlayMode = struct {
    spdp: SpDp,
    diff: Diff,
    mod: Mod = .mmod,
    modValue: f32 = 1.0,
};

pub const Simfile = struct {
    summary: Summary,
    chart: Chart,
    pub fn initAlloc(self: *Simfile, allocator: Allocator) !void {
        try self.summary.initAlloc(allocator);
        try self.chart.initAlloc(allocator);
    }
    pub fn new(allocator: Allocator) !*Simfile {
        var simfile = try allocator.create(Simfile);
        simfile.summary = try Summary.new(allocator);
        simfile.chart = try Chart.new(allocator);
        return simfile;
    }
};

/// SM format
const Summary = struct {
    title: [128]u8,
    artist: [128]u8,
    bpms: []Gimmick,
    stops: []Gimmick,
    offset: f32,
    pub fn initAlloc(self: *Summary, allocator: Allocator) !void {
        self.bpms = try allocator.alloc(Gimmick, MAX_BPMS);
        self.stops = try allocator.alloc(Gimmick, MAX_STOPS);
    }
    pub fn new(allocator: Allocator) !Summary {
        var summary = try allocator.create(Summary);
        summary.bpms = try allocator.alloc(Gimmick, MAX_BPMS);
        summary.stops = try allocator.alloc(Gimmick, MAX_STOPS);
        return summary.*;
    }
};

const Gimmick = struct {
    beat: f32 = 0,
    time: f32 = 0,
    value: f32 = 0, // Duration of stop or new bpm value
    fn asc(lhs: Gimmick, rhs: Gimmick) bool {
        return lhs.beat < rhs.beat;
    }
};

const Chart = struct {
    spdp: SpDp,
    diff: Diff,
    level: u8 = 0,
    mod: Mod,
    modValue: f32,

    guides: []Guide,
    notes: []Note,
    pub fn initAlloc(self: *Chart, allocator: Allocator) !void {
        self.guides = try allocator.alloc(Guide, MAX_GUIDES);
        self.notes = try allocator.alloc(Note, MAX_NOTES);
    }
    pub fn new(allocator: Allocator) !Chart {
        var chart = try allocator.create(Chart);
        chart.guides = try allocator.alloc(Guide, MAX_GUIDES);
        chart.notes = try allocator.alloc(Note, MAX_NOTES);
        return chart.*;
    }
};

const SpDp = enum {
    Sp,
    Dp,
    pub fn toSmString(self: SpDp) []const u8 {
        return switch (self) {
            .Sp => "dance-single",
            .Dp => "dance-double",
        };
    }
};
const Diff = enum {
    Beginner,
    Easy,
    Medium,
    Hard,
    Challenge,
    pub fn toSmString(self: Diff) []const u8 {
        return @tagName(self);
    }
};

const Note = struct {
    column: u3, // arrow column (0-indexed: p1-ldur p2-ldur)
    type: NoteType = .sentinel,
    denominator: u8, // # of lines measure is broken into: 4 = quarter notes, 8 = eighth notes etc.
    numerator: u8, // line of appearance (1-indexed)
    timeArrival: f32, // arrival time (sec)
    pub fn setTimeArrival(self: *Note) void {
        self.timeArrival = -1;
    }

    const NoteType = enum(u8) {
        sentinel = '0',
        note,
        hold,
        tail,
        roll,
        mine = 'M',
        fake = 'F',
    };
};

const Guide = struct {
    mode: enum { off, border, center } = .center,
    timeArrival: f32, // relevant in CMOD
};

/// Parse SM simfile.
pub fn parseSimfileAlloc(allocator: Allocator, filename: []const u8, playMode: PlayMode) !?*Simfile {
    //// Alternative allocation
    // const simfile = try allocator.create(Simfile);
    // try simfile.initAlloc(allocator);
    const simfile = try Simfile.new(allocator);
    var summary = simfile.summary;
    var chart = simfile.chart;

    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    var bufReader = std.io.bufferedReader(file.reader());
    var reader = bufReader.reader();
    var readBuf: [MAX_SIMFILE_BYTES]u8 = undefined;

    log.debug("About to parse {s}", .{filename});
    sec_blk: while (try reader.readUntilDelimiterOrEof(&readBuf, ';')) |section| {
        // Prune comments (replace with space)
        if (std.mem.indexOf(u8, section, "//")) |i_com| {
            const i_nl = std.mem.indexOf(u8, section[i_com..], "\n").?;
            const tmp = &section;
            for (i_com..i_nl) |ii| {
                tmp.*[ii] = ' ';
            }
        }

        // Split "tag:data"
        const i_tag = std.mem.indexOf(u8, section, "#").?;
        const i_col = std.mem.indexOf(u8, section, ":").?;
        assert(i_tag < i_col);
        const tag = section[i_tag + 1 .. i_col];
        const data = section[i_col + 1 ..];

        // Parse tags defiend in Chart
        inline for (comptime std.meta.fields(Summary)) |field| {
            var buf: [64]u8 = undefined;
            const fieldUpper = std.ascii.upperString(&buf, field.name);
            if (std.mem.eql(u8, fieldUpper, tag)) {
                const SummaryFields = std.meta.FieldEnum(Summary);
                const key = std.meta.stringToEnum(SummaryFields, field.name).?;
                switch (key) {
                    .title => {
                        _ = try std.fmt.bufPrintZ(&summary.title, "{s}", .{data});
                    },
                    .artist => {
                        _ = try std.fmt.bufPrintZ(&summary.artist, "{s}", .{data});
                    },
                    .bpms => {
                        log.debug("Parsing #BPMS:{s}", .{data});
                        _ = try parseGimmick(summary.bpms, data);
                    },
                    .stops => {
                        log.debug("Parsing #STOPS:{s}", .{data});
                        _ = try parseGimmick(summary.stops, data);
                    },
                    .offset => {
                        summary.offset = try std.fmt.parseFloat(@TypeOf(summary.offset), data);
                    },
                }
                break;
            }
        }

        // Parse "NOTES" tag
        if (std.mem.eql(u8, tag, "NOTES")) {
            if (parseNotesSection(&chart, data, playMode)) |_| {
                timeGimmicks(summary.bpms, summary.stops);
                break :sec_blk;
            } else {
                continue :sec_blk;
            }
            print("---------------\n", .{});
            print("Sp/Dp:{s}\n", .{summary.spdp.toSmString()});
            print("Diff:{s}\n", .{summary.diff.toSmString()});
            print("Level:{d}\n", .{summary.level});
            print("---------------\n", .{});
            break :sec_blk;
        }
        // Check all necessary fields have been found
    }

    return simfile;
}

fn timeGimmicks(bpms: []Gimmick, stops: []Gimmick) void {
    var i_s: u16 = 0;
    var i_b: u16 = 0;

    var bpmPrev = bpms[0].value;
    var beatPrev = 0 * bpms[0].beat;
    var time = 0 * bpms[0].time; // TODO: offset
    while (true) {
        var branch: enum { doStop, doBpm } = undefined;
        if (i_s >= stops.len and i_b >= bpms.len) {
            break;
        } else if (i_s >= stops.len) {
            branch = .doBpm;
            log.debug("----stop {}/{}, bpm {}/{} @ {d:.0}----{s}", .{
                i_s,
                stops.len,
                i_b,
                bpms.len,
                bpms[i_b].beat,
                @tagName(branch),
            });
        } else if (i_b >= bpms.len) {
            branch = .doStop;
            log.debug("----stop {}/{} @ {d:.0}, bpm {}/{}----{s}", .{
                i_s,
                stops.len,
                stops[i_s].beat,
                i_b,
                bpms.len,
                @tagName(branch),
            });
        } else {
            branch = if (stops[i_s].beat <= bpms[i_b].beat) .doStop else .doBpm;
            log.debug("----stop {}/{} @ {d:.0}, bpm {}/{} @ {d:.0}----{s}", .{
                i_s,
                stops.len,
                stops[i_s].beat,
                i_b,
                bpms.len,
                bpms[i_b].beat,
                @tagName(branch),
            });
        }

        const gim = if (branch == .doStop) &stops[i_s] else &bpms[i_b];
        const dt = (gim.beat - beatPrev) / bpmPrev * 60;
        time += dt;
        gim.time = time;
        log.debug("beatPrev {d:.0}, bpmPrev {d:.0}, time {d:.1}", .{ beatPrev, bpmPrev, time });
        log.debug("beat {d:.0}, value {d:.1}, dt {d:.1}", .{ gim.beat, gim.value, dt });

        // prep next iteration
        beatPrev = gim.beat;
        switch (branch) {
            .doStop => {
                time += gim.value;
                i_s += 1;
            },
            .doBpm => {
                bpmPrev = gim.value;
                i_b += 1;
            },
        }
    }
}

/// Gimmicks have the string format:
/// <beat>=<value>,<beat>=<value>,...
fn parseGimmick(stops: []Gimmick, data: []const u8) ![]Gimmick {
    var it = std.mem.splitScalar(u8, data, ',');
    var i_stop: u16 = 0;
    while (it.next()) |stopStr| : (i_stop += 1) {
        const i_eq = std.mem.indexOf(u8, stopStr, "=").?;
        var stop = &stops[i_stop];
        stop.beat = try std.fmt.parseFloat(@TypeOf(stop.beat), stopStr[0..i_eq]);
        stop.value = try std.fmt.parseFloat(@TypeOf(stop.value), stopStr[i_eq + 1 ..]);
        log.debug("{}:{s} -> {d:.0},{d:.2}", .{ i_stop, stopStr, stop.beat, stop.value });
    }
    log.debug("{} stops found.", .{i_stop});
    return stops[0..i_stop];
}

fn parseNotesSection(chart: *Chart, data: []const u8, playMode: PlayMode) ?*Chart {
    var it = std.mem.splitScalar(u8, data, ':');
    // Expect 6 subsections:
    //  0.sp/dp
    //  1.description
    //  2.Diff
    //  3.Level
    //  4.Groove
    //  5.Notes
    // return null if 0 or 2 don't match user selection
    var i_sub: u3 = 0;
    while (it.next()) |subsectionRaw| : (i_sub += 1) {
        const subsection = std.mem.trim(u8, subsectionRaw, " \r\n\t");
        switch (i_sub) {
            0 => {
                if (!std.mem.eql(u8, subsection, playMode.spdp.toSmString())) {
                    return null;
                }
                chart.spdp = playMode.spdp;
            },
            1 => {
                // print("description:{s}\n", .{subsection});
            },
            2 => {
                if (!std.mem.eql(u8, subsection, playMode.diff.toSmString())) {
                    return null;
                }
                chart.diff = playMode.diff;
            },
            3 => {
                chart.level = std.fmt.parseInt(u8, subsection, 0) catch 0;
            },
            4 => {
                // print("Groove: {s}\n", .{subsection});
            },
            5 => {
                chart.notes = parseMeasures(chart.notes, subsection);
            },
            else => {
                log.err("Too many ':' found in #NOTES section");
                unreachable;
            },
        }
    }
    return chart;
}

fn parseMeasures(notes: []Note, data: []const u8) []Note {
    var i_note: u10 = 0;

    var measureIt = std.mem.splitScalar(u8, data, ',');
    var i_meas: u8 = 0;
    while (measureIt.next()) |measureRaw| : (i_meas += 1) {
        const measure = std.mem.trim(u8, measureRaw, " \r\n\t");

        var denominator: u8 = @intCast(std.mem.count(u8, measure, "\n"));
        var lineIt = std.mem.splitScalar(u8, measure, '\n');
        var numerator: u8 = 1;
        while (lineIt.next()) |line| : (numerator += 1) {
            for (line, 0..) |c, column| {
                switch (c) {
                    '0', '\r' => {},
                    '\n' => {
                        denominator += 1;
                    },
                    '1', '2', '3', '4', 'M', 'F' => {
                        notes[i_note].type = @enumFromInt(c);
                        notes[i_note].denominator = denominator;
                        notes[i_note].numerator = numerator;
                        notes[i_note].column = @intCast(column);
                        i_note += 1; // next note
                    },
                    else => {
                        log.err("unexpected '{c}'\n", .{c});
                        unreachable;
                    },
                }
            }
        }
    }
    return notes;
}
