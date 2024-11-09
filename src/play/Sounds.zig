const rl = @import("raylib");

pub var clap: rl.Sound = undefined;

pub fn init() void {
    clap = rl.loadSound("./resources/clap.ogg");
}
pub fn deinit() void {
    rl.unloadSound(clap);
}
