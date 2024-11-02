const std = @import("std");
const rl = @import("raylib");
const sm = @import("./simfile.zig");
const play = @import("./play.zig");
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

    //--------------------------------------------------------------------------------------
    // Memory
    //--------------------------------------------------------------------------------------
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpaAllocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpaAllocator);
    defer arena.deinit();
    const arenaAllocator = arena.allocator();

    const filename = "./simfiles/Electronic Sports Complex/Electronic Sports Complex.sm";
    const simfile = try sm.parseSimfileAlloc(arenaAllocator, filename, playMode);

    // const GameState = enum {
    //     Menu, Options, Browse, Play
    // };
    // var gameState: GameState = .Play;
    try play.init(arenaAllocator, music, simfile.chart);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        //----------------------------------------------------------------------------------
        // Update
        //----------------------------------------------------------------------------------
        rl.updateMusicStream(music);

        // TODO: instead check all notes finished to determine hasChartEnded
        if (play.hasSongEnded()) {
            rl.stopMusicStream(music);
            rl.closeWindow();
        }

        //----------------------------------------------------------------------------------
        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);

        rl.drawText(play.getTimePlayedMsg(), 190, 200, 20, rl.Color.light_gray);
        rl.drawFPS(10, 10);
        //----------------------------------------------------------------------------------
    }

    _ = arena.reset(.retain_capacity);
}
