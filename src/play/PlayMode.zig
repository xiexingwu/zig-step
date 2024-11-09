const PlayMode = @This();

spdp: SpDp,
diff: Diff,
mod: Mod = .mmod,
modValue: f32 = 1.0,
constant: ?f32 = null, // ms until note should show

autoplay: bool = true,
assistClap: bool = true,
debug: bool = true,

pub const SpDp = enum {
    Sp,
    Dp,
    pub fn toSmString(self: SpDp) []const u8 {
        return switch (self) {
            .Sp => "dance-single",
            .Dp => "dance-double",
        };
    }
};

pub const Diff = enum {
    Beginner,
    Easy,
    Medium,
    Hard,
    Challenge,
    pub fn toSmString(self: Diff) []const u8 {
        return @tagName(self);
    }
};
pub const Mod = enum {
    mmod,
    cmod,
};
