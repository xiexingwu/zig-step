pub const packages = struct {
    pub const @"12202f8c415153088be8df39a51e0a4c9d402afd403422a0dcc9afdd417e437a6fdb" = struct {
        pub const build_root = "/Users/xiexingwu/.cache/zig/p/12202f8c415153088be8df39a51e0a4c9d402afd403422a0dcc9afdd417e437a6fdb";
        pub const build_zig = @import("12202f8c415153088be8df39a51e0a4c9d402afd403422a0dcc9afdd417e437a6fdb");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "raylib", "1220d1c8697d41a42d4eaaf3f8709865534d1f3d6ad63f8a27500fa881380651a1c5" },
            .{ "raygui", "122062b24f031e68f0d11c91dfc32aed5baf06caf26ed3c80ea1802f9e788ef1c358" },
        };
    };
    pub const @"122062b24f031e68f0d11c91dfc32aed5baf06caf26ed3c80ea1802f9e788ef1c358" = struct {
        pub const build_root = "/Users/xiexingwu/.cache/zig/p/122062b24f031e68f0d11c91dfc32aed5baf06caf26ed3c80ea1802f9e788ef1c358";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"1220d1c8697d41a42d4eaaf3f8709865534d1f3d6ad63f8a27500fa881380651a1c5" = struct {
        pub const build_root = "/Users/xiexingwu/.cache/zig/p/1220d1c8697d41a42d4eaaf3f8709865534d1f3d6ad63f8a27500fa881380651a1c5";
        pub const build_zig = @import("1220d1c8697d41a42d4eaaf3f8709865534d1f3d6ad63f8a27500fa881380651a1c5");
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "raylib-zig", "12202f8c415153088be8df39a51e0a4c9d402afd403422a0dcc9afdd417e437a6fdb" },
};
