// Notice pulse: a faint bright ring runs in toward the space the world has cleared for the viewer and brakes outside its rim,
// where it fades. Behind the ring everything shivers for a moment, like skin after a touch. It repeats while the viewer stays.
// Needs Notice_Common.hlsl (and the Idle_* macros) included first.
// q is a dot's distance from the rim in steps of Notice_Clear_QUNIT (1 = on the rim, bigger = further out), worked out by
// Notice_Body in Notice_Clear.hlsl. The ring is a function of the clock alone, so there is nothing to remember.
// How long the ring takes to come in (sweep) and where it stops (stop, in steps outside the rim) are Inspector inputs of the veil.

#ifndef NOTICE_PULSE_INCLUDED
#define NOTICE_PULSE_INCLUDED

// Quiet seconds between two rings. Bigger = rarer pulses.
#define Notice_Pulse_GAP 2.0
// Where the ring starts, in steps outside the rim. Bigger = it enters from further out (beyond the frame is fine).
#define Notice_Pulse_FAR 7.0
// Half-width of the bright band, in steps. Bigger = a broader, softer ring.
#define Notice_Pulse_WIDTH 0.28
// Seconds the ring stays at the stopping line, fading, after it arrives.
#define Notice_Pulse_DWELL 0.9
// Extra alpha at the band's peak (1 + this). Bigger = a more obvious ring.
#define Notice_Pulse_GAIN 1.2
// Extra color brightness at the peak (1 + this). Too high burns out where dots overlap.
#define Notice_Pulse_LIGHT 0.5
// Pull toward warm white at the peak. 0 = keep the ribbon's own hue; 1 = fully warm white.
#define Notice_Pulse_WARM 0.55
// Extra dot size at the peak (1 + this). Bigger = a fatter, softer glow in the band.
#define Notice_Pulse_SIZE 0.35
// Shiver amplitude, in screen half-heights (so it looks the same at every depth). Bigger = a coarser shake.
#define Notice_Pulse_TREMOR 0.012
// Distance behind the ring (steps) over which the shiver dies out. Bigger = a longer trail.
#define Notice_Pulse_TAIL 1.5
// Shiver frequency, Hz. Each dot gets its own rate within +40%, so the shake is grain, not a pulsing sheet.
#define Notice_Pulse_FREQ 13.0

/// Hidden
void Notice_Pulse(inout float3 pos, inout float3 color, inout float alpha, inout float sizeMul,
                  uint id, float q, float scale, float w, float clock, float sweep, float stop)
{
    float period = sweep + Notice_Pulse_GAP;
    float tc = clock - period * floor(clock / period);
    // The ring brakes: fast at first, easing to a stop at the stopping line.
    float x = saturate(tc / sweep);
    float e = 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x);
    float qf = lerp(Notice_Pulse_FAR, stop, e);
    float fade = 1.0 - smoothstep(sweep, sweep + Notice_Pulse_DWELL, tc);

    // The band itself: brighter, warmer, a bit fatter.
    float bq = q - qf;
    float band = exp(-(bq * bq) / (Notice_Pulse_WIDTH * Notice_Pulse_WIDTH)) * fade * w;
    alpha *= 1.0 + Notice_Pulse_GAIN * band;
    color *= 1.0 + Notice_Pulse_LIGHT * band;
    color = lerp(color, float3(1.0, 0.88, 0.68), saturate(Notice_Pulse_WARM * band));
    sizeMul *= 1.0 + Notice_Pulse_SIZE * band;

    // Shiver behind the ring (outside it, since it comes in): eased in over the band's width so nothing starts with a jolt,
    // fading with distance from it and off at the end of the cycle (the ring restarts there).
    float trail = smoothstep(0.0, Notice_Pulse_WIDTH, bq) * exp(-max(bq, 0.0) / Notice_Pulse_TAIL)
                * (1.0 - smoothstep(period - 1.0, period, tc));
    float fq = Notice_Pulse_FREQ * (1.0 + 0.4 * Idle_Rand(id, 233)) * clock;
    float2 shake = float2(sin(Idle_TAU * frac(fq + Idle_Rand(id, 231))),
                          sin(Idle_TAU * frac(1.27 * fq + Idle_Rand(id, 232))));
    pos.xy += shake * (Notice_Pulse_TREMOR * scale * w * trail);
}

#endif
