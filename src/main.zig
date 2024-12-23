const std = @import("std");
const log = std.log;

const rl = @import("raylib");

const Simfile = @import("./simfile/Simfile.zig");
const Play = @import("./play/Play.zig");
const screen = @import("./screen.zig");
const sounds = @import("./play/Sounds.zig");

pub const appState = struct {
    pub var showDebug = true;
    pub var masterVolume: f32 = 0.5;

    pub var playMode = Play.PlayMode{
        .spdp = .Sp,
        .diff = .Hard,
        .mod = .mmod,
        .modValue = 3.5,
        .constant = 800,
    };
};

pub fn main() anyerror!void {
    rl.setTraceLogLevel(.log_none);
    //--------------------------------------------------------------------------------------
    // Initialization
    //--------------------------------------------------------------------------------------
    rl.initWindow(screen.dims.width, screen.dims.height, "zig-step");
    defer rl.closeWindow();

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    sounds.init();
    defer sounds.deinit();

    screen.init();
    defer screen.deinit();
    //--------------------------------------------------------------------------------------
    // Load User/Play config
    //--------------------------------------------------------------------------------------
    const playMode = &appState.playMode;

    // const title = "Electronics Sports Complex";
    // const title = "Gravity Collapse";
    // const title = "mathematical good-bye";
    const title = "ANTI ANTHEM";
    //--------------------------------------------------------------------------------------
    // Load Music
    //--------------------------------------------------------------------------------------
    const music: rl.Music = rl.loadMusicStream("./simfiles/" ++ title ++ "/" ++ title ++ ".ogg");
    rl.playMusicStream(music);

    //--------------------------------------------------------------------------------------
    // Memory
    //--------------------------------------------------------------------------------------
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpaAllocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpaAllocator);
    defer arena.deinit();
    const arenaAllocator = arena.allocator();

    const filename = "./simfiles/" ++ title ++ "/" ++ title ++ ".sm";
    const simfile = try Simfile.fromFile(arenaAllocator, filename, playMode);

    // const GameState = enum {
    //     Menu, Options, Browse, Play
    // };
    // var gameState: GameState = .Play;
    try Play.init(arenaAllocator, music, simfile, playMode);
    defer Play.deinit();

    // Main game loop
    log.debug("-----STARTING GAME LOOP------", .{});
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        //----------------------------------------------------------------------------------
        // Update
        //----------------------------------------------------------------------------------
        rl.updateMusicStream(music);

        if (Play.hasSongEnded()) {
            rl.stopMusicStream(music);
            rl.closeWindow();
        }
        appState.showDebug = if (rl.isKeyReleased(.key_f)) !appState.showDebug else appState.showDebug;

        updateAppState();

        Play.updateBeat();
        Play.judgeArrows();
        //----------------------------------------------------------------------------------
        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        Play.Lane.draw(Play.state);

        Play.drawTimePlayedMsg();
        if (appState.showDebug) {
            screen.drawDebug(appState);
        }
        //----------------------------------------------------------------------------------
    }

    _ = arena.reset(.retain_capacity);
}

fn updateAppState() void {
    if (rl.isKeyPressed(.key_j)) appState.masterVolume -= 0.05;
    if (rl.isKeyPressed(.key_k)) appState.masterVolume += 0.05;
    appState.masterVolume = @max(0, @min(1, appState.masterVolume));
    rl.setMasterVolume(appState.masterVolume);

    if (rl.isKeyPressed(.key_h)) appState.playMode.modValue -= 0.25;
    if (rl.isKeyPressed(.key_l)) appState.playMode.modValue += 0.25;
}
