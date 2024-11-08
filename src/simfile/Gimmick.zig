const Gimmick = @This();

pub const GimmickType = enum(u2) { bpm, stop, nil };

type: GimmickType = .nil,
beat: f32 = 0,
time: f32 = 0,
value: f32 = 0, // Duration of stop or new bpm value


pub fn lessThan(_: @TypeOf(.{}), lhs: Gimmick, rhs: Gimmick) bool {
    if (lhs.beat < rhs.beat) return true;
    if (lhs.beat == rhs.beat) {
        return @intFromEnum(lhs.type) <= @intFromEnum(rhs.type);
    }
    return false;
}
