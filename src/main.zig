const std = @import("std");
const rl = @import("raylib");
const sm = @import("./simfile.zig");
const assert = std.debug.assert;
const print = std.debug.print;


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
    const playMode = sm.PlayMode{
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

    //--------------------------------------------------------------------------------------
    // Memory
    //--------------------------------------------------------------------------------------
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpaAllocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpaAllocator);
    defer arena.deinit();
    const arenaAllocator = arena.allocator();

    const simfile = "./simfiles/Electronic Sports Complex/Electronic Sports Complex.sm";
    _ = try sm.parseSimfileAlloc(arenaAllocator, simfile, playMode);

    // const GameState = enum {
    //     Menu, Options, Browse, Play
    // };
    // var gameState: GameState = .Play;
    var msgTimePlayed: [32:0]u8 = undefined;

    var hasChartEnded = false;
    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        //----------------------------------------------------------------------------------
        // Update
        //----------------------------------------------------------------------------------
        rl.updateMusicStream(music);
        const timePlayed = rl.getMusicTimePlayed(music);
        _ = try std.fmt.bufPrintZ(&msgTimePlayed, "{d:0>2.0}:{d:0>2.0}.{d:0>2.0}", .{ @divTrunc(timePlayed, 60), @rem(timePlayed, 60), @rem(timePlayed, 1) * 100 });

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
