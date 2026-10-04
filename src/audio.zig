const std = @import("std");

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + t * (b - a);
}

pub const Synth = struct {
    gen: SynthGen,
    freq: f32 = 440,
    volume: f32 = 0.2,
    gain: f32 = 0,
    playing: bool = false,
    time: f32 = 0,
    release_time: ?f32 = null,
    sample_rate: f32,

    pub fn init(gen: SynthGen, sample_rate: f32) Synth {
        return .{ .gen = gen, .sample_rate = sample_rate };
    }

    pub fn noteOn(self: *Synth, freq: f32) void {
        self.time = 0;
        self.release_time = null;
        self.freq = freq;
        self.playing = true;
    }

    pub fn noteOff(self: *Synth) void {
        if (self.playing and self.release_time == null) self.release_time = 0;
    }

    pub fn fill(self: *Synth, out: []f32) void {
        if (!self.playing and self.gain == 0) {
            @memset(out, 0);
            return;
        }
        const sounding = self.gen.fill(out, self.freq, self.sample_rate, self.time, self.release_time);
        if (!sounding) self.playing = false;

        const target: f32 = if (self.playing) 1 else 0;
        const step = 1.0 / (0.005 * self.sample_rate);
        for (out) |*s| {
            if (self.gain < target) {
                self.gain = @min(target, self.gain + step);
            } else if (self.gain > target) {
                self.gain = @max(target, self.gain - step);
            }
            s.* *= self.gain * self.volume;
        }

        const dt = @as(f32, @floatFromInt(out.len)) / self.sample_rate;
        self.time += dt;
        if (self.release_time) |*r| r.* += dt;
    }
};

pub const SynthGen = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        fill: *const fn (ptr: *anyopaque, out: []f32, freq: f32, sample_rate: f32, time: f32, release_time: ?f32) bool,
    };

    pub fn fill(self: SynthGen, out: []f32, freq: f32, sample_rate: f32, time: f32, release_time: ?f32) bool {
        return self.vtable.fill(self.ptr, out, freq, sample_rate, time, release_time);
    }

    pub fn from(impl: anytype) SynthGen {
        const T = std.meta.Child(@TypeOf(impl));
        const gen = struct {
            fn fillImpl(ptr: *anyopaque, out: []f32, freq: f32, sample_rate: f32, time: f32, release_time: ?f32) bool {
                const self: *T = @ptrCast(@alignCast(ptr));
                return self.fill(out, freq, sample_rate, time, release_time);
            }
            const vtable = VTable{ .fill = fillImpl };
        };
        return .{ .ptr = impl, .vtable = &gen.vtable };
    }
};

pub const SineGen = struct {
    phase: f32 = 0,

    pub fn fill(self: *SineGen, out: []f32, freq: f32, sample_rate: f32, time: f32, release_time: ?f32) bool {
        _ = time;
        for (out) |*s| {
            s.* = @sin(2.0 * std.math.pi * self.phase);
            self.phase = @mod(self.phase + freq / sample_rate, 1.0);
        }
        return release_time == null;
    }
};

pub const SquareGen = struct {
    phase: f32 = 0,

    pub fn fill(self: *SquareGen, out: []f32, freq: f32, sample_rate: f32, time: f32, release_time: ?f32) bool {
        _ = time;
        for (out) |*s| {
            s.* = if (self.phase < 0.5) 0.5 else -0.5;
            self.phase = @mod(self.phase + freq / sample_rate, 1.0);
        }
        return release_time == null;
    }
};

pub const TriangleGen = struct {
    phase: f32 = 0,

    pub fn fill(self: *TriangleGen, out: []f32, freq: f32, sample_rate: f32, time: f32, release_time: ?f32) bool {
        _ = time;
        for (out) |*s| {
            s.* = 4.0 * @abs(self.phase - 0.5) - 1.0;
            self.phase = @mod(self.phase + freq / sample_rate, 1.0);
        }
        return release_time == null;
    }
};

pub const ADSRSineGen = struct {
    phase: f32 = 0,
    attack: f32 = 0.05,
    decay: f32 = 0.1,
    release: f32 = 0.5,
    sustain_amp: f32 = 0.5,
    amp: f32 = 0,
    start_amp: f32 = 0,

    fn level(self: *ADSRSineGen, t: f32) f32 {
        if (t <= self.attack) return lerp(self.start_amp, 1.0, t / self.attack);
        if (t <= self.attack + self.decay) return lerp(1.0, self.sustain_amp, (t - self.attack) / self.decay);
        return self.sustain_amp;
    }

    pub fn fill(self: *ADSRSineGen, out: []f32, freq: f32, sample_rate: f32, time: f32, release_time: ?f32) bool {
        if (time == 0) self.start_amp = self.amp;
        for (out, 0..) |*s, i| {
            const dt = @as(f32, @floatFromInt(i)) / sample_rate;
            const t = time + dt;
            var amp = self.level(t);
            if (release_time) |r0| {
                const r = r0 + dt;
                amp = lerp(self.level(t - r), 0.0, @min(r / self.release, 1.0));
            }
            self.amp = amp;
            s.* = amp * @sin(2.0 * std.math.pi * self.phase);
            self.phase = @mod(self.phase + freq / sample_rate, 1.0);
        }
        if (release_time) |r| return r < self.release;
        return true;
    }
};

pub const ADSRSquareGen = struct {
    phase: f32 = 0,
    attack: f32 = 0.05,
    decay: f32 = 0.1,
    release: f32 = 0.5,
    sustain_amp: f32 = 0.5,
    amp: f32 = 0,
    start_amp: f32 = 0,

    fn level(self: *ADSRSquareGen, t: f32) f32 {
        if (t <= self.attack) return lerp(self.start_amp, 1.0, t / self.attack);
        if (t <= self.attack + self.decay) return lerp(1.0, self.sustain_amp, (t - self.attack) / self.decay);
        return self.sustain_amp;
    }

    pub fn fill(self: *ADSRSquareGen, out: []f32, freq: f32, sample_rate: f32, time: f32, release_time: ?f32) bool {
        if (time == 0) self.start_amp = self.amp;
        for (out, 0..) |*s, i| {
            const dt = @as(f32, @floatFromInt(i)) / sample_rate;
            const t = time + dt;
            var amp = self.level(t);
            if (release_time) |r0| {
                const r = r0 + dt;
                amp = lerp(self.level(t - r), 0.0, @min(r / self.release, 1.0));
            }
            self.amp = amp;
            s.* = amp * @as(f32, if (self.phase < 0.5) 0.5 else -0.5);
            self.phase = @mod(self.phase + freq / sample_rate, 1.0);
        }
        if (release_time) |r| return r < self.release;
        return true;
    }
};

pub const ADSRTriangleGen = struct {
    phase: f32 = 0,
    attack: f32 = 0.05,
    decay: f32 = 0.1,
    release: f32 = 0.5,
    sustain_amp: f32 = 0.5,
    amp: f32 = 0,
    start_amp: f32 = 0,

    fn level(self: *ADSRTriangleGen, t: f32) f32 {
        if (t <= self.attack) return lerp(self.start_amp, 1.0, t / self.attack);
        if (t <= self.attack + self.decay) return lerp(1.0, self.sustain_amp, (t - self.attack) / self.decay);
        return self.sustain_amp;
    }

    pub fn fill(self: *ADSRTriangleGen, out: []f32, freq: f32, sample_rate: f32, time: f32, release_time: ?f32) bool {
        if (time == 0) self.start_amp = self.amp;
        for (out, 0..) |*s, i| {
            const dt = @as(f32, @floatFromInt(i)) / sample_rate;
            const t = time + dt;
            var amp = self.level(t);
            if (release_time) |r0| {
                const r = r0 + dt;
                amp = lerp(self.level(t - r), 0.0, @min(r / self.release, 1.0));
            }
            self.amp = amp;
            s.* = amp * (4.0 * @abs(self.phase - 0.5) - 1.0);
            self.phase = @mod(self.phase + freq / sample_rate, 1.0);
        }
        if (release_time) |r| return r < self.release;
        return true;
    }
};
