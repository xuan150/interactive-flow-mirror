// Sketch 09 idle 光紗 (look-dev, throwaway): particles live on twisting ribbons (the "reference domain" of
// docs/refs/new_test/test.md), spread over three depth layers so they fill the frame, above a wavy horizon that mirrors them.
// Position, color and alpha are a pure function of (particleId, age), so there is no simulation: the shape is the
// envelope of many particles. Where a ribbon turns edge-on to the camera its particles overlap and the Additive blend
// lights the fold; face-on it stays a thin veil.
// age doubles as the clock: every particle lives ~forever and spawns in the first frame, so age = total time.
// Two entry points share one body: L09Veil (the world) and L09VeilReflect (the same particles mirrored under the horizon,
// used by a second VisualEffect with a smaller capacity). Their inputs show up as exposed properties in the Inspector.

#define L09_TAU 6.2831853
#define L09_RIBBONS 11
// Thin strands per ribbon (the fine striations in the reference).
#define L09_STRANDS 24
// World units for the middle layer; each layer scales them by L09_LS.
#define L09_WIDTH 2.4
#define L09_THICK 0.06
// Full turns of twist along the ribbon.
#define L09_TWIST 1.6
// Structure speed (turns per second of the slow wobble) and flow speed (fraction of the ribbon length per second).
#define L09_MOTION 0.5
#define L09_FLOW 0.015
// Edges: a few strands wander out to this many extra half-widths, so the outline dissolves into dust.
#define L09_HALO 2.0

// Set from the block's inputs at the top of each entry point (see the doc comments there for what they do).
static float L09_ALPHA = 0.45;
static float L09_SIZE = 0.035;
static float L09_BRIGHT = 1.0;
static float L09_FOG = 0.6;
static float L09_FAR_ALPHA = 0.55;
static float L09_HORIZON = -0.8;
static float L09_WAVE = 0.1;
static float L09_REFL = 0.4;
static float L09_LINE_ALPHA = 0.25;
static float L09_COLOR_SPREAD = 1.0;
static float L09_COLOR_SHIFT = 0.0;
static float L09_GAP = 1.8;
static float L09_GATHER = 0.6;
static float L09_EXTEND = 5.0;
static float L09_GLOW = 0.7;

// Horizon: a wavy line on the screen, at height L09_HORIZON on average (screen -1..1), rising and falling by L09_WAVE and
// drifting slowly. The camera is at z = L09_CAM_Z looking straight ahead, vertical FOV 35, aspect 2:1. Every particle is
// compared with the line at its own screen position; the ribbons stay above it and under it is the mirror.
// A few particles sit on the line itself and draw it, broken up, so it is never a ruler-straight stroke.
#define L09_CAM_Z (-14.0)
#define L09_TANH 0.3153
#define L09_SLOPE (-L09_HORIZON * L09_TANH)
// How soft the "no crossing" rule is (world units): ribbons ease onto the line instead of cutting off.
#define L09_MARGIN 0.25
// How fast the mirror fades with height above the line, and how much it ripples.
#define L09_REFL_FADE 4.0
#define L09_RIPPLE 0.06
// Share of particles that draw the horizon line, and its thickness in screen units.
#define L09_LINE_SHARE 0.07
#define L09_LINE_THICK 0.08

// Depth cues. The camera is at z = -14; f runs 0 (near layer) to 1 (far layer). Far = fainter, bluer (fades into the fog
// color), finer; near = brighter, deeper color, bigger and sparser.
#define L09_DEPTH_Z 18.0
#define L09_NEAR_SIZE 1.3
#define L09_FAR_SIZE 0.8
static const float3 L09_FOG_COLOR = float3(0.04, 0.08, 0.25);

// Layers, near to far: depth (z), size scale (same for all, so perspective alone makes far things small), ribbon length.
// Ribbon -> layer, height of its middle line above the horizon, share of the particles, and its place in the palette.
static const float L09_LZ[3] = { 0.0, 8.0, 18.0 };
static const float L09_LS[3] = { 0.9, 1.0, 1.0 };
static const float L09_LL[3] = { 22.0, 34.0, 52.0 };
static const uint L09_RL[L09_RIBBONS] = { 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 2 };
static const float L09_RY[L09_RIBBONS] = { 1.2, 4.0, 1.0, 3.6, 6.4, 1.0, 3.2, 5.6, 8.4, 11.4, 14.4 };
static const float L09_RW[L09_RIBBONS] = { 4.0, 4.0, 3.0, 3.0, 3.0, 3.3, 3.3, 3.3, 3.3, 3.3, 3.3 };
static const float L09_RC[L09_RIBBONS] = { 0.62, 0.80, 0.30, 0.52, 0.90, 0.12, 0.40, 0.70, 0.22, 0.95, 0.58 };
#define L09_RW_SUM 36.8

// ---- Evolution. Each event picks one ribbon and one kind of change over a stretch of it:
//   split  - the stretch forks into two branches that sway on their own; one swings back and overlaps the other;
//   gather - the stretch draws in toward its middle, denser and warmer, then lets go;
//   extend - some strands of the stretch sweep out in a new direction (any angle) and ease back.
// All of them are functions of (ribbon, u, strand, time): both ends of the stretch stay attached to the ribbon and every
// particle moves along a continuous path, so nothing resets. The stretch is fixed in the ribbon's own coordinates and
// particles keep flowing through it. Which strands take part is decided by the strand itself, along a wandering
// boundary, so changes peel strand by strand.
// 0 = the plain veil (A/B check).
#define L09_EVOLVE 1
// Events running at once. Each extra one is the same schedule delayed by L09_SLOT_PHASE seconds, with its own picks.
#define L09_SLOTS 2
#define L09_SLOT_PHASE 21.5
// Seconds. The first event starts at L09_START, later ones a random 0..L09_GAP_JIT after the quiet gap.
#define L09_START 5.0
#define L09_T_SPLIT 6.0
#define L09_T_DRIFT 6.0
#define L09_T_REUNITE 8.0
#define L09_T_RELEASE 10.0
#define L09_GAP_MIN 8.0
#define L09_GAP_JIT 5.0
// Only these ribbons take part: ones high enough to stay clear of the horizon and big enough to read.
#define L09_EVENT_RIBBONS 3
static const uint L09_EVENT_R[L09_EVENT_RIBBONS] = { 1, 3, 4 };
// Chances (out of 10) of split, and of split or gather; the rest is extend.
#define L09_P_SPLIT 4
#define L09_P_GATHER 7
// Length of the stretch (world units, along the ribbon).
#define L09_SPAN 9.0
// How wide the transition between the strands that take part and the others is, in strand positions (-1..1), and how
// much the boundary wanders.
#define L09_BLEND 0.45
#define L09_WANDER 0.35
// Split: how much the returning branch overshoots the other one (1 = just meets, >1 = overlaps), sway of each branch, and
// how far the branches part in depth (fraction of the half-width).
#define L09_MERGE 1.15
#define L09_SWAY 0.35
#define L09_DEPTH 0.35

struct L09Fx
{
    float dW;       // offset across the ribbon, world units
    float dN;       // offset through the ribbon
    float du;       // shift along the ribbon, in u
    float vs;       // scale of the strand position
    float glow;     // extra brightness
    float3 ext;     // offset in any direction (extend)
};

/// Hidden
uint L09_Pcg(uint v)
{
    uint s = v * 747796405u + 2891336453u;
    uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
    return (w >> 22u) ^ w;
}

/// Hidden
float L09_Rand(uint id, uint k)
{
    return (L09_Pcg(id * 9781u + k * 6271u) & 0xFFFFFFu) / 16777216.0;
}

/// Hidden
float3 L09_Center(float u, uint r, float t)
{
    // Centerline of ribbon r: a long irregular arc across the frame and beyond it, each ribbon with its own phase.
    uint l = L09_RL[r];
    float s = L09_LS[l];
    float x = (u - 0.5) * L09_LL[l];
    float z = L09_LZ[l] + 0.9 * s * sin(L09_TAU * (0.8 * u + 0.3 * r + 0.04 * t));
    float y = -L09_SLOPE * (z - L09_CAM_Z) + L09_RY[r] + s * (1.5 * sin(L09_TAU * (0.55 * u + 0.17 * r + 0.05 * t))
                                                            + 0.6 * sin(L09_TAU * (1.3 * u - 0.11 * t + 0.37 * r)));
    return float3(x, y, z);
}

/// Hidden
float3 L09_Palette(float x)
{
    // md palette (deep blue -> cold blue -> lilac -> pink-purple -> warm pink -> warm gold), sRGB, converted to linear below.
    const float3 c[6] = {
        float3(0.137, 0.227, 0.475), float3(0.396, 0.655, 0.922), float3(0.639, 0.545, 0.910),
        float3(0.851, 0.647, 0.859), float3(0.945, 0.722, 0.773), float3(1.000, 0.835, 0.647) };
    x = saturate(x) * 5.0;
    int i = min((int)x, 4);
    return pow(max(lerp(c[i], c[i + 1], x - i), 0.0), 2.2);
}

/// Hidden
float L09_Line(float nx, float time)
{
    // Screen height (-1..1) of the horizon at screen x = nx.
    return L09_HORIZON + L09_WAVE * (0.6 * sin(2.1 * nx + 0.05 * time) + 0.4 * sin(5.3 * nx - 0.08 * time + 1.7));
}

/// Hidden
void L09_Evolve(uint r, float u, float v, uint id, float h, float time, uint slot, inout L09Fx fx)
{
    // Adds the effect of the event running in `slot` on a particle of ribbon r at position u, strand v.
    const float total = L09_T_SPLIT + L09_T_DRIFT + L09_T_REUNITE + L09_T_RELEASE;
    const float cycle = total + L09_GAP_MIN + L09_GAP_JIT;
    float tt = time - slot * L09_SLOT_PHASE;
    if (tt < 0.0) return;
    float k = floor(tt / cycle);
    uint seed = (uint)k * 31u + slot * 1013u + 7u;
    float e = tt - k * cycle - (k < 0.5 ? L09_START : L09_GAP_JIT * L09_Rand(seed, 20));
    if (e <= 0.0 || e >= total) return;
    if (r != L09_EVENT_R[(uint)(L09_Rand(seed, 30) * L09_EVENT_RIBBONS) % L09_EVENT_RIBBONS]) return;
    uint kind = (uint)(L09_Rand(seed, 40) * 10.0);

    // One curve per phase, so the phases overlap smoothly instead of switching.
    float open = smoothstep(0.0, L09_T_SPLIT, e);
    float back = smoothstep(L09_T_SPLIT + L09_T_DRIFT, L09_T_SPLIT + L09_T_DRIFT + L09_T_REUNITE, e);
    float release = smoothstep(total - L09_T_RELEASE, total, e);
    float live = open * (1.0 - release);

    // The stretch grows from its middle; x runs 0..1 along it.
    float span = L09_SPAN / L09_LL[L09_RL[r]];
    float uc = 0.5 + (L09_Rand(seed, 31) - 0.5) * 0.3;
    float len = span * (0.35 + 0.65 * open);
    float x = (u - (uc - 0.5 * len)) / len;
    if (x <= 0.0 || x >= 1.0) return;

    // Which side of a wandering boundary this strand is on, softly: 0 .. 1.
    float sgn = L09_Rand(seed, 32) < 0.5 ? -1.0 : 1.0;
    float q = sgn * (v + L09_WANDER * sin(L09_TAU * (1.7 * u + 0.9 * r + 0.03 * time)) + 0.15 * (L09_Rand(id, 15) - 0.5));
    float b = 0.5 + 0.5 * tanh(q / L09_BLEND);

    if (kind < L09_P_SPLIT)
    {
        float g = pow(max(sin(3.14159 * x), 0.0), 1.5);
        float swayA = 1.0 + L09_SWAY * sin(L09_TAU * (0.9 * u + 0.045 * time + L09_Rand(seed, 33)));
        float swayB = 1.0 + L09_SWAY * sin(L09_TAU * (0.9 * u - 0.060 * time + L09_Rand(seed, 34)));
        float sideA = -open * swayA;
        float sideB = lerp(open * swayB, L09_MERGE * sideA, back);
        float fade = g * (1.0 - release);
        fx.dW += lerp(sideA, sideB, b) * L09_GAP * h * fade;
        fx.dN += (2.0 * b - 1.0) * open * (1.0 - back) * L09_DEPTH * h * fade;
        fx.glow += L09_GLOW * fade * open;
    }
    else if (kind < L09_P_GATHER)
    {
        // Draw in toward the middle (along and across), slowly breathing. The pull stays below 1 so the mapping never folds.
        float w = 0.5 + 0.5 * cos(3.14159 * (2.0 * x - 1.0));
        float pull = min(L09_GATHER, 0.9) * live * (1.0 + 0.12 * sin(L09_TAU * (0.11 * time + L09_Rand(seed, 35))));
        fx.du += pull * (uc - u) * w;
        fx.vs *= 1.0 - 0.55 * w * live;
        fx.glow += L09_GLOW * w * live;
    }
    else
    {
        // Some strands sweep out in a new direction; slow to rise, quicker to come back. Zero at both ends.
        float a = L09_TAU * L09_Rand(seed, 41);
        float3 dir = float3(cos(a), sin(a), 0.6 * (L09_Rand(seed, 42) - 0.5));
        float prof = x * sqrt(max(1.0 - x, 0.0)) / 0.385;
        float sel = smoothstep(0.1, 0.6, 1.0 - b);
        fx.ext += dir * (L09_EXTEND * live * prof * sel);
        fx.glow += L09_GLOW * 0.6 * live * prof * sel;
    }
}

/// Hidden
void L09_Core(inout VFXAttributes attributes, bool mirror)
{
    uint id = attributes.particleId;
    float t = attributes.age * L09_MOTION;

    // The horizon line: particles on it at every distance, spread across the frame, a few pixels thick, brighter in
    // patches that drift along it.
    if (L09_Rand(id, 8) < L09_LINE_SHARE)
    {
        float z = 10.0 + 600.0 * pow(L09_Rand(id, 11), 1.6);
        float d = z - L09_CAM_Z;
        float nx = (L09_Rand(id, 10) - 0.5) * 2.1;
        float sd = L09_Rand(id, 12) * L09_Rand(id, 12) * L09_LINE_THICK * d * L09_TANH;
        float3 p = float3(nx * d * L09_TANH * 2.0, L09_Line(nx, attributes.age) * d * L09_TANH + sd, z);
        float patch = 0.5 + 0.5 * sin(6.3 * nx + 0.2 * attributes.age) * sin(2.7 * nx - 0.13 * attributes.age + 0.8);
        attributes.position = p;
        attributes.color = L09_Palette(0.05 + 0.3 * L09_Rand(id, 13)) * L09_BRIGHT;
        attributes.alpha = mirror ? 0.0 : L09_LINE_ALPHA * (0.4 + 0.6 * L09_Rand(id, 14)) * (0.25 + 1.5 * patch);
        attributes.size = 0.0013 * d;
        return;
    }

    // Pick a ribbon by its share of the particles.
    float pick = L09_Rand(id, 0) * L09_RW_SUM;
    uint r = 0;
    for (; r < L09_RIBBONS - 1; r++)
    {
        if (pick < L09_RW[r]) break;
        pick -= L09_RW[r];
    }
    float s = L09_LS[L09_RL[r]];
    float u = frac(L09_Rand(id, 1) + attributes.age * L09_FLOW * (0.5 + L09_Rand(id, 2)));

    float h0 = L09_WIDTH * s * (0.3 + 0.7 * (0.5 + 0.5 * sin(L09_TAU * (1.1 * u + 0.23 * r - 0.07 * t))));
    float halo = L09_HALO * pow(L09_Rand(id, 9), 6.0);
    float v = ((floor(L09_Rand(id, 3) * 24.0) + 0.5 * L09_Rand(id, 4)) / 24.0) * 2.0 - 1.0;
    v *= 1.0 + halo;

    L09Fx fx;
    fx.dW = 0.0;
    fx.dN = 0.0;
    fx.du = 0.0;
    fx.vs = 1.0;
    fx.glow = 0.0;
    fx.ext = 0.0;
#if L09_EVOLVE
    for (uint e = 0; e < L09_SLOTS; e++)
        L09_Evolve(r, u, v, id, h0, attributes.age, e, fx);
#endif

    // Local frame at the (possibly shifted) place on the ribbon: T along it, W across it, N through its thickness.
    // W turns around T as u grows (twist).
    float ue = u + fx.du;
    float3 c = L09_Center(ue, r, t);
    float3 T = normalize(L09_Center(ue + 0.01, r, t) - L09_Center(ue - 0.01, r, t));
    float3 A = normalize(cross(T, float3(0, 0, 1)));
    float3 B = cross(T, A);
    float phi = L09_TAU * (L09_TWIST * ue + 0.2 * r + 0.06 * t);
    float3 W = cos(phi) * A + sin(phi) * B;
    float3 N = cross(T, W);
    float pinch = 0.5 + 0.5 * sin(L09_TAU * (1.1 * ue + 0.23 * r - 0.07 * t));
    float h = L09_WIDTH * s * (0.3 + 0.7 * pinch);

    float3 pos = c + W * (v * fx.vs * h + fx.dW) + N * ((L09_Rand(id, 5) - 0.5) * L09_THICK * s + fx.dN) + fx.ext;

    float f = saturate(pos.z / L09_DEPTH_Z);
    float fade = smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.88, u);
    float alpha = L09_ALPHA * fade * (0.6 + 0.4 * L09_Rand(id, 6)) * (1.0 - 0.5 * saturate(halo / L09_HALO))
                * lerp(1.0, L09_FAR_ALPHA, f) * (1.0 + fx.glow);

    // Color: each ribbon has its own place in the palette, drifting slowly along its length; far things fade into the fog
    // color; the active stretch of an event turns toward a warm white.
    float hue = 0.5 + (L09_RC[r] - 0.5) * L09_COLOR_SPREAD + L09_COLOR_SHIFT
              + 0.16 * sin(L09_TAU * (0.7 * u + 0.04 * t + 0.21 * r));
    float3 color = lerp(L09_Palette(hue), L09_FOG_COLOR, L09_FOG * f);
    color = lerp(color, float3(1.0, 0.80, 0.55), saturate(fx.glow * 0.5));

    // Never below the horizon: what would sink is eased onto the line and fades, so it piles up as a soft contact edge.
    float d = pos.z - L09_CAM_Z;
    float lineY = L09_Line(pos.x / (d * L09_TANH * 2.0), attributes.age) * d * L09_TANH;   // the line, at this depth
    float sd = pos.y - lineY;
    if (sd < L09_MARGIN)
    {
        float sd2 = L09_MARGIN * exp((sd - L09_MARGIN) / L09_MARGIN);
        alpha *= exp(-0.6 * (L09_MARGIN - sd) / L09_MARGIN);
        pos.y += sd2 - sd;
        sd = sd2;
    }
    if (mirror)
    {
        // The same particle flipped about the line: dimmer, bluer, rippling a little, fainter the higher the original is.
        pos.y = lineY - sd;
        pos.x += L09_RIPPLE * sd * sin(1.7 * sd - attributes.age * 0.6 + pos.x * 0.3);
        alpha *= L09_REFL * exp(-sd / L09_REFL_FADE);
        color = lerp(color, L09_FOG_COLOR, 0.35);
    }

    attributes.position = pos;
    attributes.color = color * L09_BRIGHT;
    attributes.alpha = alpha;
    attributes.size = L09_SIZE * lerp(L09_NEAR_SIZE, L09_FAR_SIZE, f) * (0.7 + 0.6 * L09_Rand(id, 7));
}

// The VFX Graph only keeps the attributes a block's function names itself, so each entry point lists them before
// handing over to the shared body.
/// alpha: Overall brightness of the dots (how much they add up where they overlap).
/// size: Dot size in world units. Perspective makes far ones smaller.
/// brightness: Color multiplier on top of alpha.
/// fog: How far distant layers fade into the dark blue background (0 = not at all).
/// farAlpha: Brightness of the farthest layer compared with the nearest.
/// horizon: Average height of the wavy horizon, -1 (bottom) .. 1 (top). Mirror lives under it.
/// wave: How much the horizon rises and falls.
/// refl: Brightness of the mirror image under the horizon (the mirror object copies this from the world).
/// lineAlpha: Brightness of the faint line drawn on the horizon.
/// colorSpread: How different the ribbons' colors are (0 = all the same, 1 = whole palette).
/// colorShift: Moves every ribbon along the palette (cold to warm).
/// forkGap: Split event: how far the two branches part, in ribbon half-widths.
/// gatherPull: Gather event: how strongly the stretch draws in (0..0.9).
/// extendLen: Extend event: how far the strands sweep out, in world units.
/// glow: Extra brightness of the part of a ribbon where an event is happening.
void L09Veil(inout VFXAttributes attributes, in float alpha, in float size, in float brightness, in float fog,
             in float farAlpha, in float horizon, in float wave, in float refl, in float lineAlpha,
             in float colorSpread, in float colorShift, in float forkGap, in float gatherPull, in float extendLen,
             in float glow)
{
    uint id = attributes.particleId;
    float age = attributes.age;
    attributes.position = attributes.position;
    attributes.color = attributes.color;
    attributes.alpha = attributes.alpha;
    attributes.size = attributes.size;
    L09_ALPHA = alpha; L09_SIZE = size; L09_BRIGHT = brightness; L09_FOG = fog; L09_FAR_ALPHA = farAlpha;
    L09_HORIZON = horizon; L09_WAVE = wave; L09_REFL = refl; L09_LINE_ALPHA = lineAlpha;
    L09_COLOR_SPREAD = colorSpread; L09_COLOR_SHIFT = colorShift; L09_GAP = forkGap; L09_GATHER = gatherPull;
    L09_EXTEND = extendLen; L09_GLOW = glow;
    L09_Core(attributes, false);
}

/// alpha: Same as the world's (kept in step by L09_Mirror).
/// size: Same as the world's.
/// brightness: Same as the world's.
/// fog: Same as the world's.
/// farAlpha: Same as the world's.
/// horizon: Same as the world's.
/// wave: Same as the world's.
/// refl: Brightness of the mirror image under the horizon (the mirror object copies this from the world).
/// lineAlpha: Same as the world's (the line is drawn only by the world).
/// colorSpread: Same as the world's.
/// colorShift: Same as the world's.
/// forkGap: Same as the world's.
/// gatherPull: Same as the world's.
/// extendLen: Same as the world's.
/// glow: Same as the world's.
void L09VeilReflect(inout VFXAttributes attributes, in float alpha, in float size, in float brightness, in float fog,
                    in float farAlpha, in float horizon, in float wave, in float refl, in float lineAlpha,
                    in float colorSpread, in float colorShift, in float forkGap, in float gatherPull,
                    in float extendLen, in float glow)
{
    uint id = attributes.particleId;
    float age = attributes.age;
    attributes.position = attributes.position;
    attributes.color = attributes.color;
    attributes.alpha = attributes.alpha;
    attributes.size = attributes.size;
    L09_ALPHA = alpha; L09_SIZE = size; L09_BRIGHT = brightness; L09_FOG = fog; L09_FAR_ALPHA = farAlpha;
    L09_HORIZON = horizon; L09_WAVE = wave; L09_REFL = refl; L09_LINE_ALPHA = lineAlpha;
    L09_COLOR_SPREAD = colorSpread; L09_COLOR_SHIFT = colorShift; L09_GAP = forkGap; L09_GATHER = gatherPull;
    L09_EXTEND = extendLen; L09_GLOW = glow;
    L09_Core(attributes, true);
}
