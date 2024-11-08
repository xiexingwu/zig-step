pub fn beatToTime(beat: f32, bpm: f32) f32 {
    return beat / bpm * 60;
}

pub fn timeToBeat(time: f32, bpm: f32) f32 {
    return bpm * time / 60;
}
