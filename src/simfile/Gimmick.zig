const Gimmick = @This();

const std = @import("std");
const inf = std.math.inf(f32);

pub const GimmickType = enum(u2) { bpm, stop, nil };

type: GimmickType = .nil,
beat: f32 = inf,
time: f32 = inf,
value: f32 = inf, // Duration of stop or new bpm value


pub fn lessThan(_: @TypeOf(.{}), lhs: Gimmick, rhs: Gimmick) bool {
    if (lhs.beat < rhs.beat) return true;
    if (lhs.beat == rhs.beat) {
        return @intFromEnum(lhs.type) <= @intFromEnum(rhs.type);
    }
    return false;
}
