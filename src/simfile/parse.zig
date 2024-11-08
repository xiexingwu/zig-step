const std = @import("std");
const log = std.log;

const Simfile = @import("./Simfile.zig");
const Gimmick = Simfile.Gimmick;

const MAX_SIMFILE_BYTES = 256 * 1024; // At time of writing, largest DDR simfile is Fascination MAXX @ 137kB
const READ_BUF_BYTES = MAX_SIMFILE_BYTES / 8;

pub const ParseError = error{
    InvalidTagSection, // Tag sections are separated by ';', with the payload in the format of "#<tag>:<content>"
    PlayModeNotFound, // Couldn't find a chart with specified play mode (SpDP or Diff)
    NoNotesParsed, // No notes parsed for the selected play mode
    SentinelNoteParsed, // Notes contain a sentinel note for whatever reason
    InsufficientMemoryProvided, // The struct provided to the parser didn't have enough memory to store the simfile content
};

pub fn parse(filename: []const u8, simfile: *Simfile) !*Simfile {
    var readBuf: [READ_BUF_BYTES]u8 = undefined;
    var chart = simfile.chart;

    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    var bufReader = std.io.bufferedReader(file.reader());
    const reader = bufReader.reader();

    log.debug("About to parse {s}", .{filename});
    var chartFound = false;
    // Iterate over one tag section at a time
    tag_blk: while (try reader.readUntilDelimiterOrEof(&readBuf, ';')) |section| {
        // Prune comments (replace with space)
        while (std.mem.indexOf(u8, section, "//")) |i_com| {
            const i_nl = std.mem.indexOf(u8, section[i_com..], "\n").?;
            // const tmp = section[i_com..i_nl];
            @memset(section[i_com..i_nl], ' ');
        }

        // Find pound and colon to split section payload into "#tag:content"
        const iPound = std.mem.indexOf(u8, section, "#");
        const iColon = std.mem.indexOf(u8, section, ":");
        if (iPound == null or iColon == null or iPound.? > iColon.?) {
            return ParseError.InvalidTagSection;
        }
        const tag = section[iPound.? + 1 .. iColon.?];
        const data = section[iColon.? + 1 ..];

        // Parse tags
        if (std.mem.eql(u8, tag, "TITLE")) _ = try std.fmt.bufPrintZ(&simfile.title, "{s}", .{data});
        if (std.mem.eql(u8, tag, "ARTIST")) _ = try std.fmt.bufPrintZ(&simfile.artist, "{s}", .{data});
        if (std.mem.eql(u8, tag, "BPMS")) chart.bpms = try parseGimmickTag(.bpm, chart.bpms, data);
        if (std.mem.eql(u8, tag, "STOPS")) chart.stops = try parseGimmickTag(.stop, chart.stops, data);
        if (std.mem.eql(u8, tag, "OFFSET")) chart.offset = try std.fmt.parseFloat(@TypeOf(chart.offset), data);
        if (std.mem.eql(u8, tag, "NOTES")) {
            // TODO Ideally this function call also has the format of returning the struct that got passed in
            // But I couldn't find a way to do that while still checking for the case that the correct chart was found
            if (try parseNotesTag(chart, data)) {
                chartFound = true;
                break :tag_blk;
            }
        }
    }

    if (!chartFound) return ParseError.PlayModeNotFound;

    return simfile;
}

/// Gimmicks have the string format:
/// <beat>=<value>,<beat>=<value>,...
fn parseGimmickTag(gimType: Gimmick.GimmickType, gimms: []Gimmick, data: []const u8) ![]Gimmick {
    log.debug("Parsing {s}:{s}", .{ @tagName(gimType), data });
    var it = std.mem.splitScalar(u8, data, ',');
    var i_gim: u16 = 0;
    while (it.next()) |gimStr| : (i_gim += 1) {
        if (i_gim >= gimms.len) return ParseError.InsufficientMemoryProvided;

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

fn parseNotesTag(chart: *Simfile.Chart, data: []const u8) !bool {
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
                if (!std.mem.eql(u8, subsection, chart.spdp.toSmString())) {
                    return false;
                }
            },
            1 => {
                // print("description:{s}\n", .{subsection});
            },
            2 => {
                if (!std.mem.eql(u8, subsection, chart.diff.toSmString())) {
                    return false;
                }
            },
            3 => {
                chart.level = std.fmt.parseInt(u8, subsection, 0) catch 0;
            },
            4 => {
                // print("Groove: {s}\n", .{subsection});
            },
            5 => {
                parseNotesBody(chart, subsection);
            },
            else => {
                log.err("Too many ':' found in #NOTES section", .{});
                return ParseError.InvalidTagSection;
            },
        }
    }

    // Check we parsed at least one note
    if (chart.notes.len == 0) return ParseError.NoNotesParsed;
    // Check notes doesn't contain sentinel
    // var noteSentinel: [1]Simfile.Note = undefined;
    // noteSentinel[0] = Simfile.Note.Note0;
    // if (std.mem.count(Simfile.Note, chart.notes, &noteSentinel) == 0) return ParseError.SentinelNoteParsed;

    return true;
}

/// Parses all the measures in the #NOTES tag
/// TODO: think about a return type that is consistent and makes sense
fn parseNotesBody(chart: *Simfile.Chart, data: []const u8) void {
    var notes = chart.notes;
    const nCols: u4 = switch (chart.spdp) {
        .Sp => 4,
        .Dp => 8,
    };

    var nMeas: u8 = 0;
    var nNotes: u16 = 0;
    var measureIt = std.mem.splitScalar(u8, data, ',');
    while (measureIt.next()) |measureRaw| : (nMeas += 1) {
        const measure = std.mem.trim(u8, measureRaw, " \r\n\t");
        nNotes += parseMeasure(notes[nNotes..], nCols, nMeas, measure);
    }
    log.debug("Parsed {d} notes\n", .{nNotes});

    chart.notes = notes[0..nNotes]; // This sets actual len for chart.notes
    chart.measures = nMeas + 1;
}

/// Parses all the notes in a single measure.
/// Treats each column as a separate note. Jumps and tails are processed separately.
fn parseMeasure(notes: []Simfile.Note, nCols: u4, nMeas: u8, data: []const u8) u16 {
    const denominator: u8 = 1 + @as(u8, @intCast(std.mem.count(u8, data, "\n")));

    var nNotes: u16 = 0;
    // Prepare to parse measure one line at a time
    var numerator: u8 = 0;
    var lineIt = std.mem.splitScalar(u8, data, '\n');
    while (lineIt.next()) |line| : (numerator += 1) {

        // Prepare to parse one line in the measure
        for (0..nCols) |col| {
            const noteType: Simfile.Note.NoteType = @enumFromInt(line[col]);
            switch (noteType) {
                .sentinel => {},
                .mine, .fake, .roll => {
                    log.debug("Unparsed noted {s}: measure {} col {}", .{ @tagName(noteType), nMeas, col });
                },
                else => {
                    notes[nNotes] = Simfile.Note{
                        .columns = Simfile.Note.getColumn(@truncate(col)),
                        .type = noteType,
                        .numerator = denominator,
                        .denominator = denominator,
                    };
                    nNotes += 1;
                },
            }
        }
    }
    return nNotes;
}
