const rl = @import("raylib");
// Load assets for single arrow to copy from

fn applyNoteConstantAlpha(note: *rl.Image, alpha: u32) *rl.Image {
    const mask = rl.genImageColor(note.width, note.height, rl.Color(0,0,0,alpha));
    return rl.imageAlphaMask(note, mask);
}
