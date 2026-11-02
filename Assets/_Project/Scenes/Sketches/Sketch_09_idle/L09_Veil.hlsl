// Sketch 09 idle 光紗 (look-dev, throwaway): particles live on twisting ribbons (the "reference domain" of
// docs/refs/new_test/test.md), spread over three depth layers so they fill the frame, above a wavy horizon that mirrors them.
// Position, color and alpha are a pure function of (particleId, age), so there is no simulation: the shape is the
// envelope of many particles. Where a ribbon turns edge-on to the camera its particles overlap and the Additive blend
// lights the fold; face-on it stays a thin veil.
// age doubles as the clock: every particle lives ~forever and spawns in the first frame, so age = total time.
// Two entry points share one body: L09Veil (the world) and L09VeilReflect (the same particles mirrored under the horizon,
// used by a second VisualEffect with a smaller capacity). Their inputs show up as exposed properties in the Inspector.

#define L09_TAU 6.2831853
#define L09_RIBBONS 6
// Thin strands per ribbon (the fine striations in the reference).
#define L09_STRANDS 24
// World units for the middle layer; each layer scales them by L09_LS.
#define L09_WIDTH 2.4
#define L09_THICK 0.25
// Full turns of twist along the ribbon.
#define L09_TWIST 1.0
// Structure speed (turns per second of the slow wobble) and flow speed (fraction of the ribbon length per second).
#define L09_MOTION 0.5
#define L09_FLOW 0.015
// Edges: a few strands wander out to this many extra half-widths, so the outline dissolves into dust.
#define L09_HALO 2.0

// 1 = the far sheets (ribbons 0-1) are loose dust spread over the whole far background, with gentle patches of denser and
// thinner dust; 0 = they are ribbons like the others.
#define L09_FAR_DUST 1

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
static float L09_GLOW = 2.0;
static float L09_XAMT = 0.8;
static float L09_XINT = 14.0;
static float L09_XDUR = 20.0;
static float L09_ZPERIOD = 30.0;
static float L09_WFOLLOW = 2.5;
static uint L09_RS = 0u;      // per-run random: mixed into every event's seed, so each start plays a different order

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
// The mirror is squashed vertically (1 = a true flip), so tall things still leave a reflection inside the frame.
#define L09_REFL_SQUASH 0.6
#define L09_RIPPLE 0.06
// Share of particles that draw the horizon line, and its thickness in screen units.
#define L09_LINE_SHARE 0.07
#define L09_LINE_THICK 0.08

// Depth cues. The camera is at z = -14; f runs 0 (near layer) to 1 (far layer). Far = fainter, bluer (fades into the fog
// color), finer; near = brighter, deeper color, bigger and sparser.
#define L09_DEPTH_Z 18.0
#define L09_NEAR_SIZE 1.3
#define L09_FAR_SIZE 0.8
// How much brighter the particles of a taking-part stretch get (giver: cooler white, receiver: warm gold), as a multiple.
#define L09_HL 2.0
static const float3 L09_FOG_COLOR = float3(0.04, 0.08, 0.25);

// Six ribbons in two roles (plus the foreground blobs, which are not ribbons):
//   A (0-1)  background: loose dust over the far background (L09_FAR_DUST), or two dim fine sheets. They never trade particles.
//   B (2-5)  the story: four ribbons that trade particles. The one that takes them gets wider and brighter, the one that
//            gives them up thinner and dimmer.
// Per ribbon: depth of its middle and how far it drifts (and at what pace), height of its middle line above the horizon (at
// that depth), share of the particles, place in the palette, width / opacity / dot size / speed multipliers.
#define L09_C0 2
#define L09_NC 4
static const float L09_ZC[L09_RIBBONS] = { 17.0, 16.0, 4.0, 8.0, 5.0, 9.0 };
static const float L09_ZA[L09_RIBBONS] = { 1.0, 1.0, 4.0, 4.0, 4.0, 4.0 };
static const float L09_ZP[L09_RIBBONS] = { 3.0, 3.0, 1.0, 1.0, 1.0, 1.0 };
static const float L09_RY[L09_RIBBONS] = { 9.3, 12.8, 2.27, 5.55, 6.89, 10.9 };
static const float L09_RW[L09_RIBBONS] = { 5.0, 5.0, 9.0, 9.0, 9.0, 9.0 };
static const float L09_RC[L09_RIBBONS] = { 0.12, 0.22, 0.52, 0.8, 0.3, 0.95 };
static const float L09_WM[L09_RIBBONS] = { 3.0, 3.0, 1.0, 1.0, 1.0, 1.0 };
static const float L09_AM[L09_RIBBONS] = { 3.6, 3.6, 1.0, 1.0, 1.0, 1.0 };
static const float L09_SM[L09_RIBBONS] = { 3.0, 3.0, 1.0, 1.0, 1.0, 1.0 };
static const float L09_SP[L09_RIBBONS] = { 0.3, 0.3, 1.0, 1.0, 1.0, 1.0 };
#define L09_RW_SUM 46.0

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

// ---- Transfer. With L09_TRANSFER 1 this runs instead of split / gather / extend. Every L09_XINT seconds or so an event starts
// (they overlap): a stretch of one ribbon sends part of its particles to another ribbon, which is the one with fewer
// particles (and the sender is one with more). Each particle leaves at its own moment and flies along a bowed path, so the
// stretch thins out gradually and nothing opens up. The move is permanent: where a particle belongs is worked out by
// replaying every event so far (the schedule is deterministic), so there is no stored state. A ribbon's width follows the
// number of particles it holds. Ribbons also drift in depth on their own (L09_Z0), so they swell and sink toward / away
// from the camera.
#define L09_TRANSFER 1

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
float L09_Z0(uint r, float age)
{
    // Depth of ribbon r's middle: a slow back-and-forth around its home depth, with its own pace and phase.
    uint k = r * 131u + 977u;
    float p = age / (L09_ZPERIOD * L09_ZP[r]);
    float a = L09_TAU * (p * (0.8 + 0.4 * L09_Rand(k, 1)) + L09_Rand(k, 2));
    float b = L09_TAU * (p * (1.9 + 0.6 * L09_Rand(k, 3)) + L09_Rand(k, 4));
    return L09_ZC[r] + L09_ZA[r] * (0.7 * sin(a) + 0.3 * sin(b));
}

/// Hidden
float3 L09_Center(float u, uint r, float t, float zb)
{
    // Centerline of ribbon r at middle depth zb: a long irregular arc across the frame and beyond it. Its length and its height
    // above the horizon grow with the distance, so it covers the same part of the screen at any depth; only its size, haze
    // and brightness change.
    float s = lerp(0.9, 1.0, saturate(zb / 8.0));
    float k = zb - L09_CAM_Z;
    float x = (u - 0.5) * 1.6 * k;
    float z = zb + 0.9 * s * sin(L09_TAU * (0.8 * u + 0.3 * r + 0.04 * t));
    float ry = L09_RY[r] * k / (L09_ZC[r] - L09_CAM_Z);
    float y = -L09_SLOPE * (z - L09_CAM_Z) + ry + s * (1.5 * sin(L09_TAU * (0.55 * u + 0.17 * r + 0.05 * t))
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
    float span = L09_SPAN / (1.6 * (L09_ZC[r] - L09_CAM_Z));
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

struct L09Pt
{
    float3 pos;
    float hue;
};

/// Hidden
L09Pt L09_At(uint r, float u, float v, uint id, float age, float ws, L09Fx fx)
{
    // Where the particle (u along, v across) sits when it belongs to ribbon r; ws scales the ribbon's width.
    float t = age * L09_MOTION * L09_SP[r];
    float zb = L09_Z0(r, age);
    float s = lerp(0.9, 1.0, saturate(zb / 8.0));
    float ue = u + fx.du;
    float3 c = L09_Center(ue, r, t, zb);
    float3 T = normalize(L09_Center(ue + 0.01, r, t, zb) - L09_Center(ue - 0.01, r, t, zb));
    float3 A = normalize(cross(T, float3(0, 0, 1)));
    float3 B = cross(T, A);
    float phi = L09_TAU * (L09_TWIST * ue + 0.2 * r + 0.06 * t);
    float3 W = cos(phi) * A + sin(phi) * B;
    float3 N = cross(T, W);
    float pinch = 0.5 + 0.5 * sin(L09_TAU * (1.1 * ue + 0.23 * r - 0.07 * t));
    float h = L09_WIDTH * s * ws * L09_WM[r] * (0.3 + 0.7 * pinch);
    L09Pt p;
    p.pos = c + W * (v * fx.vs * h + fx.dW) + N * ((L09_Rand(id, 5) - 0.5) * L09_THICK * s + fx.dN) + fx.ext;
    p.hue = 0.5 + (L09_RC[r] - 0.5) * L09_COLOR_SPREAD + L09_COLOR_SHIFT
          + 0.16 * sin(L09_TAU * (0.7 * u + 0.04 * t + 0.21 * r));
    return p;
}

struct L09Hop
{
    uint cur;       // the ribbon the particle belongs to (the one it is flying to, while it flies)
    uint prev;      // the ribbon it came from; the same as cur unless it is flying
    float away;     // 0 .. 1 progress of the flight from prev to cur
    float wsCur;    // width scale of cur
    float wsPrev;
    float brCur;    // brightness scale of cur
    float brPrev;
    float bow;      // sideways bend of the flight, signed, one side per event
    float sgn;      // which side of the strands the arrivals lean to
    float lean;     // how much of that lean the move applies
    float dU;       // downstream drift along the ribbon gained by the move
    bool moved;     // the particle has taken at least one flight
    float hlS;      // 0 .. 1 highlight while it sits in the stretch an event is taking particles from
    float hlD;      // 0 .. 1 highlight while it sits in the stretch an event is delivering to
};

/// Hidden
L09Hop L09_Track(uint id, uint r0, float time, float v, float u)
{
    // Replays every transfer event up to now for this particle. Event j starts at a jittered multiple of L09_XINT (the
    // jitter is smaller than the interval, so events stay in order) and lasts L09_XDUR. The expected number of particles on
    // each ribbon (nl, at the end of every event; nv, as the events progress) steers which ribbon gives and which takes.
    const float D0 = L09_XDUR;
    L09Hop h;
    h.cur = r0;
    h.prev = r0;
    h.away = 1.0;
    h.wsCur = 1.0;
    h.wsPrev = 1.0;
    h.brCur = 1.0;
    h.brPrev = 1.0;
    h.bow = 0.0;
    h.sgn = 1.0;
    h.lean = 0.0;
    h.dU = 0.0;
    h.moved = false;
    h.hlS = 0.0;
    h.hlD = 0.0;
    if (r0 < L09_C0) return h;      // only the event ribbons trade
    float nl[L09_RIBBONS];
    float nv[L09_RIBBONS];
    for (uint i = 0; i < L09_RIBBONS; i++)
    {
        nl[i] = L09_RW[i] / L09_RW_SUM;
        nv[i] = nl[i];
    }
    float tau = -1.0;           // when the particle's latest move starts
    float tr = 1.0;             // how long that flight takes
    float lastArrive = -1.0;
    uint lastDst = 99u;
    uint jmax = (uint)(time / L09_XINT) + 1u;
    [loop]
    for (uint j = 0; j <= jmax; j++)
    {
        uint seed = j * 7919u + 101u + L09_RS;
        float D = D0 * (0.65 + 0.7 * L09_Rand(seed, 10));       // each event runs at its own length
        // Event j starts somewhere in its own slot, early enough to be over before the next slot begins: events never overlap
        // (as long as L09_XDUR is shorter than L09_XINT), whatever the run seed.
        float start = L09_XINT * (j + 0.3) + max(0.0, L09_XINT - D) * L09_Rand(seed, 1);
        if (start > time) break;

        // Who gives and who takes: of two random event ribbons the fuller one gives, and it hands over to the emptier of its
        // neighbours (mostly the next one, sometimes the one after), so the flight is short and reads as a bridge.
        uint a1 = L09_C0 + (uint)(L09_Rand(seed, 2) * L09_NC) % L09_NC;
        uint a2 = L09_C0 + (uint)(L09_Rand(seed, 3) * L09_NC) % L09_NC;
        // Whoever received last time is not the giver this time, so a ribbon is never still glowing from taking when it
        // starts to give.
        if (a1 == lastDst) a1 = L09_C0 + (a1 - L09_C0 + 1u) % L09_NC;
        if (a2 == lastDst) a2 = L09_C0 + (a2 - L09_C0 + 1u) % L09_NC;
        uint src = nl[a1] >= nl[a2] ? a1 : a2;
        // The receiver is the emptier of two random candidates, never the giver and never the one that received last time, so
        // the taking rotates around the ribbons instead of piling up on one.
        uint c1 = L09_C0 + (uint)(L09_Rand(seed, 11) * L09_NC) % L09_NC;
        uint c2 = L09_C0 + (uint)(L09_Rand(seed, 12) * L09_NC) % L09_NC;
        for (uint k = 0; k < 3; k++)
        {
            if (c1 == src || c1 == lastDst) c1 = L09_C0 + (c1 - L09_C0 + 1u) % L09_NC;
            if (c2 == src || c2 == lastDst) c2 = L09_C0 + (c2 - L09_C0 + 1u) % L09_NC;
        }
        uint dst = nl[c1] <= nl[c2] ? c1 : c2;
        lastDst = dst;

        // The stretch (in u) and how many of its particles go. The edge of the stretch is soft.
        float span = 0.4 + 0.3 * L09_Rand(seed, 7);
        // Each event leans one way: 0 side shift (crosses over, a little lean), 1 seep (leaves from one side of the strands,
        // few and slow), 2 lopsided pile (lands on one side of the receiver).
        const float AMT[3] = { 1.0, 0.6, 0.85 };
        const float SIDE[3] = { 0.2, 0.9, 0.5 };
        const float LEAN[3] = { 0.25, 0.1, 0.6 };
        const float BOW[3] = { 0.16, 0.06, 0.1 };
        uint tend = (uint)(L09_Rand(seed, 60) * 3.0) % 3u;
        float sgn = L09_Rand(seed, 61) < 0.5 ? -1.0 : 1.0;
        float dirU = L09_Rand(seed, 62) < 0.5 ? -1.0 : 1.0;
        float share = saturate(L09_XAMT * (0.7 + 0.3 * L09_Rand(seed, 8)) * AMT[tend]);
        float uc = 0.5 + (L09_Rand(seed, 9) - 0.5) * 0.4;
        float moved = nl[src] * span * share * 0.45;
        // The giver thins first, the receiver thickens last.
        float lamS = smoothstep(start + 0.2 * D, start + 0.85 * D, time);
        float lamD = smoothstep(start + 0.4 * D, start + 1.2 * D, time);
        nl[src] -= moved;
        nl[dst] += moved;
        nv[src] -= lamS * moved;
        nv[dst] += lamD * moved;

        // Who is taking part, as a glow 0..1 that every particle works out for itself. A giver ramps up before it leaves, a
        // receiver flares as it lands and holds until the last arrival, and the rest of both stretches brighten faintly.
        float us = frac(L09_Rand(id, 1) + start * L09_FLOW * (0.5 + L09_Rand(id, 2)));
        float e = abs(us - uc) / (0.5 * span);
        float gu = exp(-4.0 * e * e);
        if (h.cur == dst)
            h.hlD = max(h.hlD, 0.45 * gu * smoothstep(start + 0.3 * D, start + 0.8 * D, time) * (1.0 - smoothstep(start + 1.3 * D, start + 1.6 * D, time)));
        if (h.cur != src) continue;
        float sideW = lerp(1.0, smoothstep(-0.8, 0.8, sgn * v), SIDE[tend]);
        if (L09_Rand(id + seed * 7919u, 57) > share * exp(-2.5 * e * e) * sideW)
        {
            h.hlS = max(h.hlS, 0.25 * gu * smoothstep(start, start + 0.4 * D, time) * (1.0 - smoothstep(start + 0.7 * D, start + 1.0 * D, time)));
            continue;
        }
        // Departures sweep along the stretch like a front.
        float sweep = saturate(0.5 + 0.5 * dirU * (us - uc) / (0.5 * span));
        float t2 = start + D * (0.25 + 0.4 * sweep + 0.1 * L09_Rand(id + seed * 131u, 50));   // never before start + 0.25 D: the glow ramp ahead of it must fit inside the event
        if (t2 < lastArrive) continue;
        float trl = D * (0.3 + 0.1 * L09_Rand(id + seed * 131u, 51)) * (tend == 1u ? 1.25 : 1.0);
        // This particle's glow in this event: it ramps up (twinkling) before it goes and lets go as it flies; the landing
        // flares and holds until the last arrival. A particle that has not gone yet keeps its earlier move and earlier glow
        // untouched, so nothing it already had is dropped when the next event starts.
        h.hlS = max(h.hlS, smoothstep(t2 - 0.25 * D, t2 - 0.02 * D, time) * (1.0 - smoothstep(t2, t2 + 0.15 * trl, time)));
        if (t2 > time) continue;
        h.hlD = max(h.hlD, smoothstep(t2 + 0.5 * trl, t2 + trl, time) * (1.0 - smoothstep(start + 1.3 * D, start + 1.6 * D, time)));
        tau = t2;
        tr = trl;
        h.bow = sgn * BOW[tend] * (0.5 + 0.5 * L09_Rand(seed, 63));
        h.sgn = sgn;
        h.lean = LEAN[tend];
        h.dU = dirU * (tend == 0u ? 0.04 : 0.02);
        lastArrive = tau + tr;
        h.prev = h.cur;
        h.cur = dst;
    }
    if (tau >= 0.0)
    {
        h.moved = time >= tau;
        if (time < tau) h.cur = h.prev;
        else if (time < tau + tr) h.away = smoothstep(0.0, 1.0, (time - tau) / tr);
        else h.prev = h.cur;
    }
    float rc = max(nv[h.cur] * L09_RW_SUM / L09_RW[h.cur], 0.05);
    float rp = max(nv[h.prev] * L09_RW_SUM / L09_RW[h.prev], 0.05);
    h.wsCur = clamp(1.0 + L09_WFOLLOW * (rc - 1.0), 0.4, 2.2);
    h.wsPrev = clamp(1.0 + L09_WFOLLOW * (rp - 1.0), 0.4, 2.2);
    h.brCur = clamp(1.0 + L09_GLOW * (rc - 1.0), 0.3, 2.5);
    h.brPrev = clamp(1.0 + L09_GLOW * (rp - 1.0), 0.3, 2.5);
    return h;
}

// ---- Condense. Every L09_CINT seconds a stretch of one B ribbon draws in dust from the far background around it: dust
// near the stretch is the likeliest to be taken (L09_CSHARE at its peak, falling off over L09_CREACH screen heights), each
// particle flies in at its own moment, speeding up as it nears, stays part of the ribbon for a while, then breathes out and
// settles back where it was, slowing down. Like the transfer, it is a function of (particle, time) with no stored state.
// The ribbon's own particles in the stretch brighten faintly while it takes the dust in; the dust that has landed glows.
#define L09_CINT 60.0
#define L09_CDUR 34.0
#define L09_CSTART 20.0
#define L09_CSHARE 1.6      // chance scale; the chance is this times the falloff, capped at 1
#define L09_CREACH 1.2      // how far from the stretch dust is still taken from, in screen heights

struct L09Cd
{
    bool on;        // an event has started (its tail is part of it)
    float sk;       // when it started
    uint rr;        // the ribbon that takes the dust in
    float uc;       // middle of its stretch, in u
    float span;     // length of the stretch, in u
    uint cs;        // seed of the event
};

/// Hidden
L09Cd L09_Cond(float age)
{
    L09Cd c;
    c.on = false;
    c.sk = 0.0;
    c.rr = L09_C0;
    c.uc = 0.5;
    c.span = 0.5;
    c.cs = 0u;
    float tc = age - L09_CSTART;
    if (tc < 0.0) return c;
    float ck = floor(tc / L09_CINT);
    c.cs = (uint)ck * 6151u + 313u + L09_RS;
    c.sk = L09_CSTART + ck * L09_CINT + (L09_CINT - L09_CDUR - 2.0) * L09_Rand(c.cs, 1);   // always inside its own slot
    c.rr = L09_C0 + (uint)(L09_Rand(c.cs, 2) * L09_NC) % L09_NC;
    c.uc = 0.5 + (L09_Rand(c.cs, 3) - 0.5) * 0.4;
    c.span = 0.4 + 0.2 * L09_Rand(c.cs, 4);
    c.on = age >= c.sk;
    return c;
}

// ---- Fly-by. Its own VFX (L09_Fly.vfx, entry L09Fly, a soft Gaussian sprite instead of the shared dot, so it can blur
// for real). Every L09_FINT seconds L09_FN particles come out of the far background toward the lens, each at its own
// moment: they idle, then speed up hard as they near, and grow with the perspective into one big soft out-of-focus glow,
// getting paler and then dazzling as they pass the lens. A flight keeps its place in the world, so the perspective carries
// it past the frame's edge, where it fades. A side show, never in the mirror.
#define L09_FINT 45.0
#define L09_FDUR 16.0       // from the first particle leaving to the last one gone
#define L09_FSTART 25.0
#define L09_FN 40u          // flights per event (= the particle capacity of L09_Fly.vfx)
#define L09_FSLOW 6.0       // how long a flight idles before it rushes: higher = slower start, faster end
#define L09_FGLARE 5.0      // how much brighter it gets as it passes the lens
#define L09_FSIZE 30.0      // extra growth of the glow at the end of the flight

struct L09Fl
{
    bool on;
    float sk;
    uint cs;
};

/// Hidden
L09Fl L09_Fly(float age)
{
    L09Fl c;
    c.on = false;
    c.sk = 0.0;
    c.cs = 0u;
    float tc = age - L09_FSTART;
    if (tc < 0.0) return c;
    float ck = floor(tc / L09_FINT);
    c.cs = (uint)ck * 4421u + 977u + L09_RS;
    c.sk = L09_FSTART + ck * L09_FINT + (L09_FINT - L09_FDUR - 6.0) * L09_Rand(c.cs, 1);   // its tail ends inside its own slot
    c.on = age >= c.sk;
    return c;
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
    float u = frac(L09_Rand(id, 1) + attributes.age * L09_FLOW * L09_SP[r] * (0.5 + L09_Rand(id, 2)));
    float halo = L09_HALO * pow(L09_Rand(id, 9), 6.0);
    // Strands: 24 of them, but unevenly spaced, so they never line up into a regular hatching.
    float si = floor(L09_Rand(id, 3) * 24.0);
    float sc = si + 0.5 + 0.8 * (L09_Rand(r * 31u + (uint)si, 74) - 0.5);
    float v = ((sc + 0.5 * (L09_Rand(id, 4) - 0.5)) / 24.0) * 2.0 - 1.0;
    v *= 1.0 + halo;

    L09Fx fx;
    fx.dW = 0.0;
    fx.dN = 0.0;
    fx.du = 0.0;
    fx.vs = 1.0;
    fx.glow = 0.0;
    fx.ext = 0.0;
#if L09_EVOLVE && !L09_TRANSFER
    float s0 = lerp(0.9, 1.0, saturate(L09_Z0(r, attributes.age) / 8.0));
    float h0 = L09_WIDTH * s0 * (0.3 + 0.7 * (0.5 + 0.5 * sin(L09_TAU * (1.1 * u + 0.23 * r - 0.07 * t))));
    for (uint e = 0; e < L09_SLOTS; e++)
        L09_Evolve(r, u, v, id, h0, attributes.age, e, fx);
#endif

    // Which ribbon it is on now (and, while it flies, which one it left), then where it sits.
    uint rc = r;
    uint rp = r;
    float away = 1.0;
    float wc = 1.0;
    float wp = 1.0;
    float bc = 1.0;
    float bp = 1.0;
#if L09_TRANSFER
    L09Hop hop = L09_Track(id, r, attributes.age, v, u);
    rc = hop.cur;
    rp = hop.prev;
    away = hop.away;
    wc = hop.wsCur;
    wp = hop.wsPrev;
    bc = hop.brCur;
    bp = hop.brPrev;
    // A particle that has moved leans toward one side of its new strands and has drifted downstream.
    float v2 = v;
    L09Fx fxa = fx;
    if (hop.moved)
    {
        v2 = lerp(v, hop.sgn * (0.35 + 0.45 * abs(v)), hop.lean * away);
        fxa.du += hop.dU * away;
    }
#else
    float v2 = v;
    L09Fx fxa = fx;
#endif
    L09Pt a = L09_At(rc, u, v2, id, attributes.age, wc, fxa);
    float3 pos = a.pos;
    float hue = a.hue;
    float moving = 0.0;
    float br = bc;
    if (rp != rc)
    {
        // In flight: from where it was on the old ribbon to where it will be on the new one, bowing to one side so the
        // particles fan out instead of running in parallel lines.
        L09Pt b = L09_At(rp, u, v, id, attributes.age, wp, fx);
        float3 delta = a.pos - b.pos;
        float2 side = normalize(float2(-delta.y, delta.x) + 1e-5);
        pos = lerp(b.pos, a.pos, away);
        pos.xy += side * (length(delta) * sin(3.14159 * away) * (hop.bow + 0.04 * (2.0 * L09_Rand(id, 45) - 1.0)));
        hue = lerp(b.hue, a.hue, away);
        moving = sin(3.14159 * away);
        br = lerp(bp, bc, away);
    }

    float amx = L09_AM[r];
    float smx = L09_SM[r];
    float uFade = 1.0;
    float cw = 0.0;         // 0 .. 1: how far a dust particle has joined a ribbon
    float cglow = 0.0;
    float cglowS = 0.0;
    bool dust = L09_FAR_DUST && r < 2u;
    if (dust)
    {
        // Uniform spots over the far frustum, bent by two slow low-frequency waves so the density varies (the bend is mild
        // enough not to fold, so no hard clumps). Always above the horizon line.
        float sx = L09_Rand(id, 70) * 2.0 - 1.0;
        float sy = L09_Rand(id, 71) * 2.0 - 1.0;
        float ph = L09_Rand(r, 72);
        float nx = sx + 0.12 * sin(L09_TAU * (0.6 * sy + 0.012 * attributes.age + ph))
                      + 0.06 * sin(L09_TAU * (1.3 * sy - 0.02 * attributes.age + 2.0 * ph));
        float ny = sy + 0.15 * sin(L09_TAU * (0.5 * sx + 0.015 * attributes.age + 3.0 * ph));
        float z = 17.0 + 13.0 * L09_Rand(id, 73);
        float dd = z - L09_CAM_Z;
        float scr = lerp(L09_Line(nx, attributes.age), 1.05, saturate(0.5 + 0.5 * ny));
        pos = float3(nx * dd * L09_TANH * 2.0 * 1.05, scr * dd * L09_TANH, z);

        // Condense: if this particle is one of the dust the running event draws in, it flies to the stretch and back.
        L09Cd cdd = L09_Cond(attributes.age);
        bool taken = false;
        if (cdd.on)
        {
            // Dust whose landing spot is near its own place is the likeliest to be taken; the landing is fixed at the event's
            // start so the choice never changes mid-event.
            float u0 = cdd.uc + (L09_Rand(id, 58) - 0.5) * cdd.span;
            float3 cc = L09_Center(u0, cdd.rr, cdd.sk * L09_MOTION * L09_SP[cdd.rr], L09_Z0(cdd.rr, cdd.sk));
            float2 ds = pos.xy / (dd * L09_TANH) - cc.xy / ((cc.z - L09_CAM_Z) * L09_TANH);
            taken = L09_Rand(id + cdd.cs * 7919u, 57) < L09_CSHARE * exp(-dot(ds, ds) / (L09_CREACH * L09_CREACH));
        }
        if (taken)
        {
            float age = attributes.age;
            float ts = cdd.sk + L09_CDUR * (0.04 + 0.26 * L09_Rand(id + cdd.cs * 131u, 50));
            float tin = L09_CDUR * 0.2;
            float tl = cdd.sk + L09_CDUR * (0.72 + 0.12 * L09_Rand(id + cdd.cs * 131u, 51));   // it stays a good while
            float tout = L09_CDUR * 0.2;
            float wi = smoothstep(ts, ts + tin, age);
            float wo = smoothstep(tl, tl + tout, age);
            cw = wi * (1.0 - wo);
            // Steady glow once landed; it hands over to the giver's twinkle as the particle gets ready to leave.
            cglow = smoothstep(ts + 0.6 * tin, ts + tin, age) * (1.0 - smoothstep(tl - 0.25 * tout, tl, age));
            cglowS = smoothstep(tl - 0.25 * tout, tl, age) * (1.0 - smoothstep(tl + 0.4 * tout, tl + tout, age));
            // In: slow start, faster near the stretch, nearly straight. Out: fast start, slowing as it settles, bending.
            float cwp = wo > 0.0 ? (1.0 - wo) * (1.0 - wo) : wi * wi;
            float cbow = wo > 0.0 ? 0.12 : 0.03;
            if (cw > 0.0)
            {
                float uL = frac(cdd.uc + (L09_Rand(id, 58) - 0.5) * cdd.span + (age - cdd.sk) * L09_FLOW * L09_SP[cdd.rr] * (0.5 + L09_Rand(id, 2)));
                L09Pt lp = L09_At(cdd.rr, uL, v, id, age, 1.0, fx);
                float3 dl = lp.pos - pos;
                float2 sdir = normalize(float2(-dl.y, dl.x) + 1e-5);
                float bowSgn = L09_Rand(cdd.cs, 5) < 0.5 ? -1.0 : 1.0;
                float3 p0 = pos;
                pos = lerp(p0, lp.pos, cwp);
                pos.xy += sdir * (length(dl) * cbow * sin(3.14159 * cwp) * bowSgn * (0.5 + 0.5 * L09_Rand(id, 45)));
                hue = lerp(hue, lp.hue, cw);
                amx = lerp(amx, L09_AM[cdd.rr], cw);
                smx = lerp(smx, L09_SM[cdd.rr], cw);
                uFade = lerp(1.0, smoothstep(0.0, 0.12, uL) * smoothstep(1.0, 0.88, uL), cw);
            }
        }
    }
    float f = saturate(pos.z / L09_DEPTH_Z);
    float fade = dust ? uFade : smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.88, u);
    float alpha = L09_ALPHA * fade * (0.6 + 0.4 * L09_Rand(id, 6)) * (1.0 - 0.5 * saturate(halo / L09_HALO))
                * lerp(1.0, L09_FAR_ALPHA, f) * (1.0 + fx.glow) * (1.0 + 1.2 * moving) * br * amx;

    // Color: each ribbon has its own place in the palette, drifting slowly along its length; far things fade into the fog
    // color; the active stretch of an event turns toward a warm white.
    float3 color = lerp(L09_Palette(hue), L09_FOG_COLOR, L09_FOG * f * (r < 2u ? 0.4 : 1.0));   // the far sheets keep most of their color
    if (dust) color = lerp(color, dot(color, float3(0.3, 0.59, 0.11)).xxx, 0.6 * (1.0 - cw));   // the far dust stays quiet: much less saturated
    color = lerp(color, float3(1.0, 0.80, 0.55), saturate(fx.glow * 0.5));
    color = lerp(color, float3(1.0, 0.85, 0.60), 0.35 * moving);   // particles in flight are brighter and warmer

    float hlS = 0.0;
    float hlD = 0.0;
#if L09_TRANSFER
    hlS = hop.hlS;
    hlD = hop.hlD;
#endif
    // The dust that has landed in a condensing stretch glows, and so does the ribbon's own part of that stretch.
    hlD = max(hlD, cglow);
    hlS = max(hlS, cglowS);
    L09Cd cd = L09_Cond(attributes.age);
    if (cd.on && !dust && rc == cd.rr)
    {
        float cu = frac(L09_Rand(id, 1) + cd.sk * L09_FLOW * (0.5 + L09_Rand(id, 2)));
        float cg = abs(cu - cd.uc) / (0.5 * cd.span);
        hlD = max(hlD, 0.4 * exp(-4.0 * cg * cg) * smoothstep(cd.sk + 0.15 * L09_CDUR, cd.sk + 0.35 * L09_CDUR, attributes.age)
                       * (1.0 - smoothstep(cd.sk + 0.8 * L09_CDUR, cd.sk + L09_CDUR, attributes.age)));
    }
    // Shine: the same hue, brighter and a little bigger. The giver twinkles as its particles get ready to leave, the receiver
    // glows steadily. Only a faint tint, so the colors stay.
    float twinkle = pow(0.5 + 0.5 * sin(L09_TAU * (0.9 * attributes.age * (0.5 + L09_Rand(id, 80)) + L09_Rand(id, 81))), 4.0);
    float shine = hlD + hlS * (0.35 + 1.3 * twinkle);
    alpha *= 1.0 + L09_HL * shine;
    color *= 1.0 + 0.8 * shine;
    color = lerp(color, float3(0.75, 0.88, 1.0), 0.12 * hlS);
    color = lerp(color, float3(1.0, 0.82, 0.55), 0.12 * hlD);

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
        pos.y = lineY - sd * L09_REFL_SQUASH;
        pos.x += L09_RIPPLE * sd * sin(1.7 * sd - attributes.age * 0.6 + pos.x * 0.3);
        alpha *= L09_REFL * exp(-sd / L09_REFL_FADE);
        color = lerp(color, L09_FOG_COLOR, 0.35);
    }

    attributes.position = pos;
    attributes.color = color * L09_BRIGHT;
    attributes.alpha = alpha;
    attributes.size = L09_SIZE * lerp(L09_NEAR_SIZE, L09_FAR_SIZE, f) * smx * (1.0 + 0.25 * moving) * (1.0 + 0.5 * shine) * (0.7 + 0.6 * L09_Rand(id, 7));
}

/// Hidden
void L09_FlyCore(inout VFXAttributes attributes)
{
    attributes.position = float3(0.0, 0.0, 0.0);
    attributes.color = float3(0.0, 0.0, 0.0);
    attributes.alpha = 0.0;
    attributes.size = 0.0;
    uint id = attributes.particleId;
    if (id >= L09_FN) return;
    L09Fl fl = L09_Fly(attributes.age);
    if (!fl.on) return;
    uint fs = fl.cs * 131u + id * 977u;
    float flyT = 4.0 + 1.5 * L09_Rand(fs, 60);
    float tS = fl.sk + (L09_FDUR - flyT) * L09_Rand(fs, 61);
    float pf = (attributes.age - tS) / flyT;
    if (pf <= 0.0 || pf >= 1.0) return;
    // Where it sits on screen at the start (in screen half-heights), never in the middle; and how far away it starts.
    float2 s0 = float2((L09_Rand(fs, 62) * 2.0 - 1.0) * 1.9, lerp(-0.7, 0.95, L09_Rand(fs, 63)));
    s0 *= max(1.0, 0.55 / max(length(s0), 1e-3));
    float dd = 31.0 + 13.0 * L09_Rand(fs, 64);
    // The flight is driven by how far it has grown on screen, so the speed across the frame keeps climbing until it leaves:
    // it starts at its place and ends 1.5 frame-edges out. Perspective then puts it that much closer to the lens.
    float e = pow(pf, L09_FSLOW);
    float edge0 = max(abs(s0.x) * 0.5, abs(s0.y));             // 1 = at the frame's edge
    float S = 1.0 + (1.5 / edge0 - 1.0) * e;
    float dn = dd / S;
    float3 pos = float3(s0 * dd * L09_TANH, L09_CAM_Z + dn);   // keeps its sideways place in the world
    float edge = edge0 * S;
    float fb = smoothstep(0.1, 0.8, e);                        // how far it has come
    float fc = smoothstep(0.1, 0.9, pf);                       // how pale
    float fg = smoothstep(0.5, 0.95, e);                       // the dazzle
    float f = saturate(pos.z / L09_DEPTH_Z);
    float vis = smoothstep(0.0, 0.12, pf) * (1.0 - smoothstep(1.05, 1.4, edge));
    float3 color = lerp(L09_Palette(0.1 + 0.85 * L09_Rand(fs, 65)), L09_FOG_COLOR, L09_FOG * f * 0.4);
    color = lerp(color, dot(color, float3(0.3, 0.59, 0.11)).xxx, 0.6 * (1.0 - fb));   // quiet when far, colorful when near
    color = lerp(color, float3(0.95, 0.97, 1.0), 0.1 * fc);   // stays colored; the glow comes from the soft sprite
    color *= 1.0 + 0.8 * fg;
    attributes.position = pos;
    attributes.color = color * L09_BRIGHT;
    attributes.alpha = L09_ALPHA * 3.6 * (0.6 + 0.4 * L09_Rand(fs, 66)) * lerp(1.0, L09_FAR_ALPHA, f) * vis * (1.0 + 0.5 * L09_FGLARE * fg);
    attributes.size = L09_SIZE * lerp(L09_NEAR_SIZE, L09_FAR_SIZE, f) * 3.0 * (1.0 + L09_FSIZE * fb) * (0.7 + 0.6 * L09_Rand(fs, 67));
}

// The VFX Graph only keeps the attributes a block's function names itself, so each entry point lists them before
// handing over to the shared body.
/// alpha: How see-through the dots are. Higher = brighter, especially where dots overlap.
/// size: Size of each dot. Far dots shrink by themselves (perspective).
/// brightness: Multiplies every color. Raise for a brighter picture.
/// fog: How much the far layers fade into the dark blue background. 0 = not at all.
/// farAlpha: How bright the farthest layer is compared with the nearest. Lower = deeper space.
/// horizon: Where the mirror line sits on screen. -1 is the bottom edge, 0 the middle.
/// wave: How much the horizon line rises and falls.
/// refl: How bright the reflection under the horizon is.
/// lineAlpha: How bright the faint line along the horizon is.
/// colorSpread: How different the ribbons' colors are. 0 = one color, 1 = the whole palette.
/// colorShift: Slides all colors along the palette. Negative = cooler, positive = warmer.
/// forkGap: Split event: how far the two branches pull apart.
/// gatherPull: Gather event: how tightly the stretch draws in (0 - 0.9).
/// extendLen: Extend event: how far the strands sweep out.
/// receiverGlow: How strongly a ribbon brightens as it takes in particles and dims as it gives them up. 0 = brightness never changes.
/// transferAmount: Transfer event: share of the particles in the chosen stretch that move to another ribbon.
/// transferEvery: Transfer events: average seconds between two events. They overlap when this is shorter than Transfer Duration.
/// transferTime: Transfer event: seconds one event takes, from the first particle leaving to the last one arriving.
/// depthPeriod: Seconds a ribbon takes to drift from near to far and back. Each ribbon keeps its own pace.
/// widthFollow: How strongly a ribbon widens as particles join it and narrows as they leave. 0 = width never changes.
/// runSeed: Random number chosen at every start; it changes which events happen in which order. 0 = the same order every time.
void L09Veil(inout VFXAttributes attributes, in float alpha, in float size, in float brightness, in float fog,
             in float farAlpha, in float horizon, in float wave, in float refl, in float lineAlpha,
             in float colorSpread, in float colorShift, in float forkGap, in float gatherPull, in float extendLen,
             in float receiverGlow, in float transferAmount, in float transferEvery, in float transferTime, in float depthPeriod,
             in float widthFollow, in float runSeed)
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
    L09_EXTEND = extendLen; L09_GLOW = receiverGlow;
    L09_XAMT = transferAmount; L09_XINT = transferEvery; L09_XDUR = transferTime; L09_ZPERIOD = depthPeriod; L09_WFOLLOW = widthFollow; L09_RS = (uint)runSeed * 2654435761u;
    L09_Core(attributes, false);
}

/// alpha: How see-through the dots are. Higher = brighter, especially where dots overlap.
/// size: Size of each dot. Far dots shrink by themselves (perspective).
/// brightness: Multiplies every color. Raise for a brighter picture.
/// fog: How much the far layers fade into the dark blue background. 0 = not at all.
/// farAlpha: How bright the farthest layer is compared with the nearest. Lower = deeper space.
/// horizon: Where the mirror line sits on screen. -1 is the bottom edge, 0 the middle.
/// wave: How much the horizon line rises and falls.
/// refl: How bright the reflection under the horizon is.
/// lineAlpha: How bright the faint line along the horizon is.
/// colorSpread: How different the ribbons' colors are. 0 = one color, 1 = the whole palette.
/// colorShift: Slides all colors along the palette. Negative = cooler, positive = warmer.
/// forkGap: Split event: how far the two branches pull apart.
/// gatherPull: Gather event: how tightly the stretch draws in (0 - 0.9).
/// extendLen: Extend event: how far the strands sweep out.
/// receiverGlow: How strongly a ribbon brightens as it takes in particles and dims as it gives them up. 0 = brightness never changes.
/// transferAmount: Transfer event: share of the particles in the chosen stretch that move to another ribbon.
/// transferEvery: Transfer events: average seconds between two events. They overlap when this is shorter than Transfer Duration.
/// transferTime: Transfer event: seconds one event takes, from the first particle leaving to the last one arriving.
/// depthPeriod: Seconds a ribbon takes to drift from near to far and back. Each ribbon keeps its own pace.
/// widthFollow: How strongly a ribbon widens as particles join it and narrows as they leave. 0 = width never changes.
/// runSeed: Random number chosen at every start; it changes which events happen in which order. 0 = the same order every time.
void L09VeilReflect(inout VFXAttributes attributes, in float alpha, in float size, in float brightness, in float fog,
                    in float farAlpha, in float horizon, in float wave, in float refl, in float lineAlpha,
                    in float colorSpread, in float colorShift, in float forkGap, in float gatherPull, in float extendLen,
                    in float receiverGlow, in float transferAmount, in float transferEvery, in float transferTime, in float depthPeriod,
                    in float widthFollow, in float runSeed)
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
    L09_EXTEND = extendLen; L09_GLOW = receiverGlow;
    L09_XAMT = transferAmount; L09_XINT = transferEvery; L09_XDUR = transferTime; L09_ZPERIOD = depthPeriod; L09_WFOLLOW = widthFollow; L09_RS = (uint)runSeed * 2654435761u;
    L09_Core(attributes, true);
}

/// alpha: How see-through the dots are. Higher = brighter, especially where dots overlap.
/// size: Size of each dot. Far dots shrink by themselves (perspective).
/// brightness: Multiplies every color. Raise for a brighter picture.
/// fog: How much the far layers fade into the dark blue background. 0 = not at all.
/// farAlpha: How bright the farthest layer is compared with the nearest. Lower = deeper space.
/// horizon: Where the mirror line sits on screen. -1 is the bottom edge, 0 the middle.
/// wave: How much the horizon line rises and falls.
/// refl: How bright the reflection under the horizon is.
/// lineAlpha: How bright the faint line along the horizon is.
/// colorSpread: How different the ribbons' colors are. 0 = one color, 1 = the whole palette.
/// colorShift: Slides all colors along the palette. Negative = cooler, positive = warmer.
/// forkGap: Split event: how far the two branches pull apart.
/// gatherPull: Gather event: how tightly the stretch draws in (0 - 0.9).
/// extendLen: Extend event: how far the strands sweep out.
/// receiverGlow: How strongly a ribbon brightens as it takes in particles and dims as it gives them up. 0 = brightness never changes.
/// transferAmount: Transfer event: share of the particles in the chosen stretch that move to another ribbon.
/// transferEvery: Transfer events: average seconds between two events. They overlap when this is shorter than Transfer Duration.
/// transferTime: Transfer event: seconds one event takes, from the first particle leaving to the last one arriving.
/// depthPeriod: Seconds a ribbon takes to drift from near to far and back. Each ribbon keeps its own pace.
/// widthFollow: How strongly a ribbon widens as particles join it and narrows as they leave. 0 = width never changes.
/// runSeed: Random number chosen at every start; it changes which events happen in which order. 0 = the same order every time.
void L09Fly(inout VFXAttributes attributes, in float alpha, in float size, in float brightness, in float fog,
            in float farAlpha, in float horizon, in float wave, in float refl, in float lineAlpha,
            in float colorSpread, in float colorShift, in float forkGap, in float gatherPull, in float extendLen,
            in float receiverGlow, in float transferAmount, in float transferEvery, in float transferTime, in float depthPeriod,
            in float widthFollow, in float runSeed)
{
    uint id = attributes.particleId;
    float age = attributes.age;
    attributes.position = attributes.position;
    attributes.color = attributes.color;
    attributes.alpha = attributes.alpha;
    attributes.size = attributes.size;
    L09_ALPHA = alpha; L09_SIZE = size; L09_BRIGHT = brightness; L09_FOG = fog; L09_FAR_ALPHA = farAlpha;
    L09_RS = (uint)runSeed * 2654435761u;
    L09_FlyCore(attributes);
}
