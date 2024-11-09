const Judgment = @This();
const std = @import("std");

nil: f32,
marvelous: f32 = 0.0167,
perfect: f32 = 0.033,
great: f32 = 0.092,
good: f32 = 0.142,
ok: f32,
miss: f32,

pub const Kind = std.meta.FieldEnum(Judgment);
