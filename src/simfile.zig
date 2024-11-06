const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const rl = @import("raylib");

const utils = @import("./utils.zig");

const MAX_BEATS = 4 * 256; // Is 256 measures for ddr songs?
const MAX_NOTES = 1024; // MAX360 CSP is 1000
const MAX_SIMFILE_BYTES = 256 * 1024; // At time of writing, largest DDR simfile is Fascination MAXX @ 137kB
const MAX_BPMS = 512; // DeltaMAX is 473
const MAX_STOPS = 128; // Chaos TTM is 70(?)

//// Types
pub const Mod = enum {
    mmod,
    cmod,
};

pub const PlayMode = struct {
    spdp: SpDp,
    diff: Diff,
    mod: Mod = .mmod,
    modValue: f32 = 1.0,
    constant: ?f32 = null, // ms until note should show
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
    gimms: []Gimmick,
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

const GimmickType = enum(u2) { bpm, stop, nil };
const Gimmick = struct {
    type: GimmickType = .nil,
    beat: f32 = 0,
    time: f32 = 0,
    value: f32 = 0, // Duration of stop or new bpm value
    fn lessThan(_: @TypeOf(.{}), lhs: Gimmick, rhs: Gimmick) bool {
        if (lhs.beat < rhs.beat) return true;
        if (lhs.beat == rhs.beat) {
            return @intFromEnum(lhs.type) <= @intFromEnum(rhs.type);
        }
        return false;
    }
};

pub const Chart = struct {
    spdp: SpDp,
    diff: Diff,
    level: u8 = 0,
    mod: Mod,
    modValue: f32,
    measures: u8,

    // beats: []Beat,
    notes: []Note,
    pub fn initAlloc(self: *Chart, allocator: Allocator) !void {
        // self.beats = try allocator.alloc(Beat, MAX_BEATS);
        self.notes = try allocator.alloc(Note, MAX_NOTES);
    }
    pub fn new(allocator: Allocator) !Chart {
        var chart = try allocator.create(Chart);
        // chart.beats = try allocator.alloc(Beat, MAX_BEATS);
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

pub const Note = struct {
    type: NoteType = .sentinel,
    column: u8 = 0, // bit-wise indication of active column (LSB is p1-left, MSB is p2-right)

    denominator: u8 = 0, // # of lines measure is broken into: 4 = quarter notes, 8 = eighth notes etc.
    numerator: u8 = 0, // line of appearance (0-indexed)
    measure: u8 = 0, // measure (0-indexed)
    time: f32 = 0, // arrival time (sec)

    pub fn getColumnChar(self: Note) u8 {
        return switch (self.column) {
            1 << 0 => 'L',
            1 << 1 => 'D',
            1 << 2 => 'U',
            1 << 3 => 'R',
            1 << 4 => 'l',
            1 << 5 => 'd',
            1 << 6 => 'u',
            1 << 7 => 'r',
            else => unreachable,
        };
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
        switch (self.type) {
            .tail, .roll, .mine, .fake => {
                return rl.Color.blank;
            },
            .sentinel => unreachable,
            else => {},
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

pub const Note0 = Note{};

// const Beat0 = Beat{};
// const Beat = struct {
//     timeArrival: f32 = 0, // relevant in CMOD
// };
const beatToTime = utils.beatToTime;

/// Parse SM simfile.
pub fn parseSimfileAlloc(allocator: Allocator, filename: []const u8, playMode: PlayMode) !*Simfile {
    //// Alternative allocation
    // const simfile = try allocator.create(Simfile);
    // try simfile.initAlloc(allocator);
    var simfile = try Simfile.new(allocator);
    var summary = &simfile.summary;
    var chart = &simfile.chart;

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
                        summary.bpms = try parseGimmick(.bpm, summary.bpms, data);
                    },
                    .stops => {
                        summary.stops = try parseGimmick(.stop, summary.stops, data);
                    },
                    .offset => {
                        summary.offset = try std.fmt.parseFloat(@TypeOf(summary.offset), data);
                    },
                    else => {},
                }
                break;
            }
        }

        // Parse "NOTES" tag, breaking if correct chart found
        if (std.mem.eql(u8, tag, "NOTES")) {
            if (parseNotesSection(chart, data, playMode)) |c| {
                // This reassignment is technically not needed since chart is
                // passed by reference. However, this maintains the pattern
                // that the parse functions return a copy of what they parse.
                chart = c;
                break :sec_blk;
            }
        }
    }

    // Assert we parsed at least one note
    assert(simfile.chart.notes[0].type != .sentinel);
    // Assert notes doesn't contain sentinel
    const len = simfile.chart.notes.len;
    const n = simfile.chart.notes[0..];
    assert(len <= MAX_NOTES and !std.meta.eql(n[len - 1], Note0));

    // Sort gimmicks and compute timings
    const gimmsConcat = [_][]Gimmick{ summary.stops, summary.bpms };
    var gimms = try std.mem.concat(allocator, Gimmick, &gimmsConcat);
    std.sort.pdq(Gimmick, gimms, .{}, Gimmick.lessThan);
    gimms = timeGimmicks(gimms);

    // Debug logs before final return
    // summary = timeGimmicksLegacy(summary);
    summary.gimms = gimms;
    simfile = timeNotes(simfile);

    log.debug("---------------", .{});
    log.debug("Sp/Dp:{s}", .{simfile.chart.spdp.toSmString()});
    log.debug("Diff:{s}", .{simfile.chart.diff.toSmString()});
    log.debug("Level:{d}", .{simfile.chart.level});
    log.debug("Measures:{d}", .{simfile.chart.measures});
    log.debug("Gimmicks:{d}", .{simfile.summary.gimms.len});
    log.debug("Bpms:{d}", .{simfile.summary.bpms.len});
    log.debug("Stops:{d}", .{simfile.summary.stops.len});
    log.debug("Notes:{d}", .{simfile.chart.notes.len});
    log.debug("---------------", .{});
    return simfile;
}

/// Determine the arrival time for all notes.
fn timeNotes(simfile: *Simfile) *Simfile {
    const chart = simfile.chart;
    const summary = simfile.summary;
    const notes = chart.notes;
    const gimms = summary.gimms;

    var i_gimm: u16 = 1; // Skip first value (sets song bpm and is not an actual gimmick)
    var i_note: u16 = 0;
    var time: f32 = 0.0;
    var bpm = summary.bpms[0].value;
    for (0..chart.measures) |meas| {
        var beatPrev: f32 = 0;
        for (0..4) |beatMeasInt| {
            const beatMeas: f32 = @floatFromInt(beatMeasInt + 1);
            defer {
                time += beatToTime(beatMeas - beatPrev, bpm);
                beatPrev = beatMeas;
            }

            // Loop over remaining notes and check if this beat in the measure
            // needs to be further split by the notes.
            while (i_note < notes.len) : (i_note += 1) {
                var note = &notes[i_note]; // Use ptr since we need to modify timing
                // Check next note is for this measure
                if (note.measure > meas) break;
                // Check next note is for this beat in the measure
                const beatNote = note.getMeasBeat();
                if (beatNote > beatMeas) break;

                // We now know beatMeas will be split by the note.
                defer {
                    time += beatToTime(beatNote - beatPrev, bpm);
                    note.time = time;
                    beatPrev = beatNote;
                    print("m{d: >2} b{d: >3}/{d: <3} = {d: >5.2}: n{} @ {c} {s} @ {d:.2}s\n", .{
                        meas,
                        note.numerator,
                        note.denominator,
                        beatNote,
                        i_note,
                        note.getColumnChar(),
                        @tagName(note.type),
                        note.time,
                    });
                }

                // Check for gimmicks
                while (i_gimm < gimms.len) : (i_gimm += 1) {
                    const gimm = gimms[i_gimm];
                    // Gimmick beat is relative to song start. Convert to measure start
                    const beatGimm = gimm.beat - 4.0 * @as(f32, @floatFromInt(meas));
                    // Check next gimmick occurs before this note
                    if (beatGimm >= beatNote) break;
                    log.debug("{d:.2}s found {s}: b{d:.2} with value {d:.2} @ {d:.2}s", .{ time, @tagName(gimm.type), gimm.beat, gimm.value, gimm.time });

                    switch (gimm.type) {
                        .bpm => {
                            // Bpm change should split the beat
                            time += beatToTime(beatGimm - beatPrev, bpm);
                            bpm = gimm.value;
                            beatPrev = beatGimm;
                            // The time should now sync with when the bpm change happens
                            assert(@abs(gimm.time - time) < 0.01);
                        },
                        .stop => {
                            // Stops should just accumulate the time
                            time += gimm.value;
                        },
                        .nil => {
                            log.err("Found unintialised gimmick when timing notes", .{});
                            unreachable;
                        },
                    }
                }
            }
        }
    }

    return simfile;
}

/// Computes timing for SORTED array of gimmicks (by time of gimmick start)
fn timeGimmicks(gimms: []Gimmick) []Gimmick {
    assert(gimms[0].type == .bpm and gimms[0].value != 0);
    var bpmPrev = gimms[0].value;
    var beatPrev = 0 * gimms[0].beat;
    var time = 0 * gimms[0].time; // TODO: offset
    for (gimms) |*gimm| {
        const dt = beatToTime(gimm.beat - beatPrev, bpmPrev);
        time += dt;
        gimm.time = time;
        print("beatPrev {d:.0}, bpmPrev {d:.0}, time {d:.1}\n", .{ beatPrev, bpmPrev, time });
        print("beat {d:.0}, value {d:.1}, dt {d:.1}\n", .{ gimm.beat, gimm.value, dt });

        // Prep next loop
        beatPrev = gimm.beat;
        switch (gimm.type) {
            .bpm => {
                bpmPrev = gimm.value;
            },
            .stop => {
                time += gimm.value;
            },
            .nil => {
                log.err("Found unitialised gimmick @ beat {d:.0}", .{gimm.beat});
                unreachable;
            },
        }
    }
    return gimms;
}

fn timeGimmicksLegacy(summary: *Summary) *Summary {
    const bpms = summary.bpms;
    const stops = summary.stops;
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

        const gimm = if (branch == .doStop) &stops[i_s] else &bpms[i_b];
        const dt = beatToTime(gimm.beat - beatPrev, bpmPrev);
        time += dt;
        gimm.time = time;
        log.debug("beatPrev {d:.0}, bpmPrev {d:.0}, time {d:.1}", .{ beatPrev, bpmPrev, time });
        log.debug("beat {d:.0}, value {d:.1}, dt {d:.1}", .{ gimm.beat, gimm.value, dt });

        // prep next iteration
        beatPrev = gimm.beat;
        switch (branch) {
            .doStop => {
                time += gimm.value;
                i_s += 1;
            },
            .doBpm => {
                bpmPrev = gimm.value;
                i_b += 1;
            },
        }
    }
    return summary;
}

/// Gimmicks have the string format:
/// <beat>=<value>,<beat>=<value>,...
fn parseGimmick(gimType: GimmickType, gimms: []Gimmick, data: []const u8) ![]Gimmick {
    log.debug("Parsing {s}:{s}", .{ @tagName(gimType), data });
    var it = std.mem.splitScalar(u8, data, ',');
    var i_gim: u16 = 0;
    while (it.next()) |gimStr| : (i_gim += 1) {
        const i_eq = std.mem.indexOf(u8, gimStr, "=").?;
        var gim = &gimms[i_gim];
        gim.type = gimType;
        gim.beat = try std.fmt.parseFloat(@TypeOf(gim.beat), gimStr[0..i_eq]);
        gim.value = try std.fmt.parseFloat(@TypeOf(gim.value), gimStr[i_eq + 1 ..]);
        log.debug("{}:{s} -> {d:.0},{d:.2}", .{ i_gim, gimStr, gim.beat, gim.value });
    }
    log.debug("{} {s}s found.", .{ i_gim, @tagName(gimType) });
    return gimms[0..i_gim];
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
                chart.measures = chart.notes[chart.notes.len - 1].measure + 1;
            },
            else => {
                log.err("Too many ':' found in #NOTES section", .{});
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

        const denominator: u8 = 1 + @as(u8, @intCast(std.mem.count(u8, measure, "\n")));
        var lineIt = std.mem.splitScalar(u8, measure, '\n');
        var numerator: u8 = 0;
        while (lineIt.next()) |line| : (numerator += 1) {
            for (line[0..4], 0..4) |char, col| {
                switch (char) {
                    '0', '\r' => {},
                    '\n' => {},
                    '1', '2', '3', '4', 'M', 'F' => {
                        notes[i_note].column = @as(u8, 1) << (3 - @as(u3, @truncate(col)));
                        notes[i_note].type = @enumFromInt(char);
                        notes[i_note].measure = i_meas;
                        notes[i_note].denominator = denominator;
                        notes[i_note].numerator = numerator;
                        i_note += 1; // next note
                    },
                    else => {
                        log.err("unexpected '{c}'\n", .{char});
                        unreachable;
                    },
                }
            }
        }
    }
    log.debug("Parsed {d} notes\n", .{i_note});
    return notes[0..i_note];
}
