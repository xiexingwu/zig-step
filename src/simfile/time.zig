const std = @import("std");
const log = std.log;

const Simfile = @import("./Simfile.zig");
const utils = @import("../utils/utils.zig");
const Gimmick = Simfile.Gimmick;
const beatToTime = utils.beatToTime;

pub fn timeAlloc(allocator: std.mem.Allocator, chart: *Simfile.Chart) !*Simfile.Chart {

    // Sort gimmicks and compute timings
    const gimmsConcat = [_][]Simfile.Gimmick{ chart.stops, chart.bpms };
    var gimms = try std.mem.concat(allocator, Gimmick, &gimmsConcat);
    std.sort.pdq(Gimmick, gimms, .{}, Gimmick.lessThan);
    gimms = timeGimmicks(gimms);

    // Debug logs before final return
    chart.gimms = gimms;
    timeNotes(chart);

    return chart;
}

/// Determine the time each gimmick starts
fn timeGimmicks(gimms: []Gimmick) []Gimmick {
    std.debug.assert(gimms[0].type == .bpm and gimms[0].beat == 0 and gimms[0].value != 0);
    var bpmPrev = gimms[0].value;
    var beatPrev = 0 * gimms[0].beat;
    var time = 0 * gimms[0].time; // TODO: offset
    for (gimms) |*gimm| {
        const dt = beatToTime(gimm.beat - beatPrev, bpmPrev);
        time += dt;
        gimm.time = time;

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

/// Determine the arrival time for all notes.
/// TODO think of return value
fn timeNotes(chart: *Simfile.Chart) void {
    const notes = chart.notes;
    const gimms = chart.gimms;

    var i_gimm: u16 = 1; // Skip first value (sets song bpm and is not an actual gimmick)
    var i_note: u16 = 0;
    var time: f32 = 0.0;
    var bpm = chart.bpms[0].value;
    var beat: f32 = 0;
    while (i_note < notes.len) : (i_note += 1) {
        var note = &notes[i_note];
        const beatNote = note.getSongBeat();

        // Check for gimmicks that occur before the next note
        while (i_gimm < gimms.len) : (i_gimm += 1) {
            const gimm = gimms[i_gimm];
            const beatGimm = gimm.beat;
            // Check gimmick occurs before this note
            if (beatGimm >= beatNote) break;
            log.debug("{d:.2}s found {s}: b{d:.2} with value {d:.2} @ {d:.2}s", .{ time, @tagName(gimm.type), gimm.beat, gimm.value, gimm.time });

            switch (gimm.type) {
                .bpm => {
                    // Bpm change should split the beat
                    time += beatToTime(beatGimm - beat, bpm);
                    bpm = gimm.value;
                    beat = beatGimm;
                    // The time should now sync with when the bpm change happens
                    std.debug.assert(@abs(gimm.time - time) < 0.01);
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

        // Prep next note
        time += beatToTime(beatNote - beat, bpm);
        note.time = time;
        beat = beatNote;
    }
}
