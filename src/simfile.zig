const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

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
};

/// SM format
const Summary = struct {
    // TODO: this shouldn't be in summary
    const TimeValue = struct {
        time: f32,
        value: f32, // Duration of stop or new bpm value
    };

    title: []u8,
    artist: []u8,
    bpms: TimeValue,
    stops: TimeValue,
    offset: f32,
};

const Chart = struct {
    spdp: SpDp,
    diff: Diff,
    level: u8 = 0,
    mod: Mod,
    modValue: f32,

    guides: []Guide,
    notes: []Note,
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
pub fn parseSimfile(allocator: Allocator, filename: []const u8, playMode: PlayMode) !void {
    const summary = try allocator.create(Summary);
    defer allocator.destroy(summary);

    const simfile = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer simfile.close();

    var bufReader = std.io.bufferedReader(simfile.reader());
    var reader = bufReader.reader();
    // At time of writing, largest DDR simfile is Fascination MAXX @ 137kB
    var readBuf: [256 * 1024]u8 = undefined;
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
                        summary.title = data;
                    },
                    .artist => {
                        summary.artist = data;
                    },
                    .bpms => {},
                    .stops => {},
                    .offset => {
                        summary.offset = try std.fmt.parseFloat(@TypeOf(summary.offset), data);
                    },
                }
                break;
            }
        }

        // Parse "NOTES" tag
        if (std.mem.eql(u8, tag, "NOTES")) {
            if (try parseNotesSection(allocator, data, playMode)) |chart| {
                _ = chart;
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
}

fn parseNotesSection(allocator: Allocator, data: []const u8, playMode: PlayMode) !?*Chart {
    const chart = try allocator.create(Chart);

    var it = std.mem.splitScalar(u8, data, ':');
    // Expect 6 subsections:
    //  0.sp/dp
    //  1.description
    //  2.Diff
    //  3.Level
    //  4.Groove
    //  5.Notes
    // return null if 0 or 2 don't match user selection
    var i_sub: u8 = 0;
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
                chart.level = try std.fmt.parseInt(u8, subsection, 0);
            },
            4 => {
                // print("Groove: {s}\n", .{subsection});
            },
            5 => {
                _ = try parseMeasures(
                    allocator,
                    subsection,
                );
            },
            else => unreachable,
        }
    }
    return chart;
}

fn parseMeasures(allocator: Allocator, data: []const u8) ![]Note {
    const notes = try allocator.alloc(Note, 1024);
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
                        print("unexpected '{c}'\n", .{c});
                        unreachable;
                    },
                    // else => unreachable,
                }
            }
        }
        // print("{}: {}, {}\n", .{ i_meas, denominator, _notes });
        // print("{s}\n", .{section});
    }
    return notes;
}
