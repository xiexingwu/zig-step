const std = @import("std");
const rl = @import("raylib");

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
const PlayMode = struct {
    spdp: SpDp,
    diff: Diff,
};
const NoteType = enum {};
const Note = struct {
    denominator: u8, // # of lines measure is broken into: 4 = quarter notes, 8 = eighth notes etc.
    numerator: u8, // line of appearance
    type: u8, // 1=note,2=hold_start,3=tail,4=roll_start,M=mine,F=fake
    timeArrival: f32, // arrival time (sec)
    pub fn setTimeArrival(self: *Note) void {
        self.timeArrival = -1;
    }
};

fn parseSimfileNotes(allocator: std.mem.Allocator, data: []const u8) ![]Note {
    const notes = try allocator.alloc(Note, 2000);
    _ = data;
    return notes;
}

fn parseSimfile(allocator: std.mem.Allocator, filename: []const u8, playMode: PlayMode) !void {
    const simfile = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer simfile.close();

    var buf_reader = std.io.bufferedReader(simfile.reader());
    var in_stream = buf_reader.reader();
    // At time of writing, largest DDR simfile is Fascination MAXX @ 137kB
    var buf: [256 * 1024]u8 = undefined;
    sec_blk: while (try in_stream.readUntilDelimiterOrEof(&buf, ';')) |section| {
        // Prune comments (replace with space)
        if (std.mem.indexOf(u8, section, "//")) |i_com| {
            const i_nl = std.mem.indexOf(u8, section[i_com..], "\n").?;
            const tmp = &section;
            for (i_com..i_nl) |ii| {
                tmp.*[ii] = ' ';
            }
        }

        // Parse sections
        const i_tag = std.mem.indexOf(u8, section, "#").?;
        const i_col = std.mem.indexOf(u8, section, ":").?;
        const tag = section[i_tag + 1 .. i_col];
        const data = section[i_col + 1 ..];

        // Special handling for #NOTES
        // Expect 6 subsections:
        //  0.sp/dp
        //  1.description
        //  2.Diff
        //  3.Level
        //  4.Groove
        //  5.Notes
        // Skip to next section if 0 or 2 don't match user selection
        if (std.mem.eql(u8, tag, "NOTES")) {
            var it = std.mem.splitScalar(u8, data, ':');

            var i_sub: u8 = 0;
            while (it.next()) |subsection| : (i_sub += 1) {
                const subtag = std.mem.trim(u8, subsection, " \r\n\t");
                switch (i_sub) {
                    0 => {
                        std.debug.print("sp/dp:{s}, user:{s}\n", .{ subtag, playMode.spdp.toSmString() });
                        if (!std.mem.eql(u8, subtag, playMode.spdp.toSmString())) {
                            continue :sec_blk;
                        }
                    },
                    1 => {
                        std.debug.print("description:{s}\n", .{subtag});
                    },
                    2 => {
                        std.debug.print("Diff:{s}, user:{s}\n", .{ subtag, playMode.diff.toSmString() });
                        if (!std.mem.eql(u8, subtag, playMode.diff.toSmString())) {
                            continue :sec_blk;
                        }
                    },
                    3 => {
                        std.debug.print("Level: {s}\n", .{subtag});
                    },
                    4 => {
                        std.debug.print("Groove: {s}\n", .{subtag});
                    },
                    5 => {
                        _ = try parseSimfileNotes(allocator, data);
                    },
                    else => unreachable,
                }
            }
            break :sec_blk;
        }
        // Check all necessary fields have been found
    }
}

pub fn main() anyerror!void {
    //--------------------------------------------------------------------------------------
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "zig-step");
    defer rl.closeWindow();
    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    //--------------------------------------------------------------------------------------
    // Load User/Play config
    //--------------------------------------------------------------------------------------
    const playMode = PlayMode{
        .spdp = .Sp,
        .diff = .Medium,
    };

    //--------------------------------------------------------------------------------------
    // Load Textures
    //--------------------------------------------------------------------------------------
    // const texture: rl.Texture = rl.Texture.init("path/to/texture.png");
    // defer rl.unloadTexture(texture);

    //--------------------------------------------------------------------------------------
    // Load Music
    //--------------------------------------------------------------------------------------
    const music: rl.Music = rl.loadMusicStream("./simfiles/Electronic Sports Complex/Electronic Sports Complex.ogg");
    rl.playMusicStream(music);
    const musicLength: f32 = rl.getMusicTimeLength(music);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpaAllocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpaAllocator);
    defer arena.deinit();
    const arenaAllocator = arena.allocator();

    const simfile = "./simfiles/Electronic Sports Complex/Electronic Sports Complex.sm";
    try parseSimfile(arenaAllocator, simfile, playMode);

    // const GameState = enum {
    //     Menu, Options, Browse, Play
    // };
    // var gameState: GameState = .Play;
    var msgTimePlayed: [32:0]u8 = undefined;

    var hasChartEnded = false;
    rl.seekMusicStream(music, musicLength * 0.95);
    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        //----------------------------------------------------------------------------------
        // Update
        //----------------------------------------------------------------------------------
        rl.updateMusicStream(music);
        const timePlayed = rl.getMusicTimePlayed(music);
        _ = try std.fmt.bufPrintZ(&msgTimePlayed, "{d:0>2.0}:{d:0>2.0}.{d:0>2.0}", .{ @divTrunc(timePlayed, 60), @rem(timePlayed, 60), @rem(timePlayed, 1) * 100 });
        // std.debug.print("{}/{}, {s}\n", .{ timePlayed, musicLength, msgTimePlayed });

        // TODO: instead check all notes finished to determine hasChartEnded
        if (timePlayed / musicLength >= 0.99) {
            hasChartEnded = true;
        } else if (hasChartEnded and timePlayed < 5) {
            // Dirty hack to check song finished the first time and prevent it
            // from looping. timePlayed cannot line up with musicLength
            // exactly, hence cull it at the beginning of the loop.
            rl.stopMusicStream(music);
            rl.closeWindow();
        }

        //----------------------------------------------------------------------------------
        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);

        rl.drawText(msgTimePlayed[0..], 190, 200, 20, rl.Color.light_gray);
        //----------------------------------------------------------------------------------
    }
}
