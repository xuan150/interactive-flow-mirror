// Idle 光紗: particles live on twisting ribbons (the "reference domain" of
// docs/refs/new_test/test.md), spread over three depth layers so they fill the frame, above a wavy horizon that mirrors them.
// Position, color and alpha are a pure function of (particleId, age), so there is no simulation: the shape is the
// envelope of many particles. Where a ribbon turns edge-on to the camera its particles overlap and the Additive blend
// lights the fold; face-on it stays a thin veil.
// age doubles as the clock: every particle lives ~forever and spawns in the first frame, so age = total time.
// Two entry points share one body: IdleVeil (the world) and IdleVeilReflect (the same particles mirrored under the horizon,
// used by a second VisualEffect with a smaller capacity). Their inputs show up as exposed properties in the Inspector.

#define Idle_TAU 6.2831853
#define Idle_RIBBONS 6
// Thin strands per ribbon (the fine striations in the reference).
#define Idle_STRANDS 24
// World units for the middle layer; each layer scales them by Idle_LS.
#define Idle_WIDTH 2.4
#define Idle_THICK 0.25
// Full turns of twist along the ribbon.
#define Idle_TWIST 1.0
// Structure speed (turns per second of the slow wobble) and flow speed (fraction of the ribbon length per second).
#define Idle_MOTION 0.5
#define Idle_FLOW 0.015
// Edges: a few strands wander out to this many extra half-widths, so the outline dissolves into dust.
#define Idle_HALO 2.0

// 1 = the far sheets (ribbons 0-1) are loose dust spread over the whole far background, with gentle patches of denser and
// thinner dust; 0 = they are ribbons like the others.
#define Idle_FAR_DUST 1

// Set from the block's inputs at the top of each entry point (see the doc comments there for what they do).
static float Idle_ALPHA = 0.45;
static float Idle_SIZE = 0.035;
static float Idle_BRIGHT = 1.0;
static float Idle_FOG = 0.6;
static float Idle_FAR_ALPHA = 0.55;
static float Idle_HORIZON = -0.8;
static float Idle_WAVE = 0.1;
static float Idle_REFL = 0.4;
static float Idle_LINE_ALPHA = 0.25;
static float Idle_COLOR_SPREAD = 1.0;
static float Idle_COLOR_SHIFT = 0.0;
static float Idle_GAP = 1.8;
static float Idle_GATHER = 0.6;
static float Idle_EXTEND = 5.0;
static float Idle_GLOW = 2.0;
static float Idle_XAMT = 0.8;
static float Idle_XINT = 14.0;
static float Idle_XDUR = 20.0;
static float Idle_ZPERIOD = 30.0;
static float Idle_WFOLLOW = 2.5;
static uint Idle_RS = 0u;      // per-run random: mixed into every event's seed, so each start plays a different order

// Horizon: a wavy line on the screen, at height Idle_HORIZON on average (screen -1..1), rising and falling by Idle_WAVE and
// drifting slowly. The camera is at z = Idle_CAM_Z looking straight ahead, vertical FOV 35, aspect 2:1. Every particle is
// compared with the line at its own screen position; the ribbons stay above it and under it is the mirror.
// A few particles sit on the line itself and draw it, broken up, so it is never a ruler-straight stroke.
#define Idle_CAM_Z (-14.0)
#define Idle_TANH 0.3153
#define Idle_SLOPE (-Idle_HORIZON * Idle_TANH)
// How soft the "no crossing" rule is (world units): ribbons ease onto the line instead of cutting off.
#define Idle_MARGIN 0.25
// How fast the mirror fades with height above the line, and how much it ripples.
#define Idle_REFL_FADE 4.0
// The mirror is squashed vertically (1 = a true flip), so tall things still leave a reflection inside the frame.
#define Idle_REFL_SQUASH 0.6
#define Idle_RIPPLE 0.06
// Share of particles that draw the horizon line, and its thickness in screen units.
#define Idle_LINE_SHARE 0.07
#define Idle_LINE_THICK 0.08

// Depth cues. The camera is at z = -14; f runs 0 (near layer) to 1 (far layer). Far = fainter, bluer (fades into the fog
// color), finer; near = brighter, deeper color, bigger and sparser.
#define Idle_DEPTH_Z 18.0
#define Idle_NEAR_SIZE 1.3
#define Idle_FAR_SIZE 0.8
// How much brighter the particles of a taking-part stretch get (giver: cooler white, receiver: warm gold), as a multiple.
#define Idle_HL 2.0
static const float3 Idle_FOG_COLOR = float3(0.04, 0.08, 0.25);

// ---- Notice (docs/notice.md): how the world reacts once it has noticed a viewer. Mode 0 = the plain idle, untouched.
// A bit mask: 1 clear, 2 pulse, 4 focus. The values come from NoticeSensor every frame.
#include "Assets/_Project/Notice/Notice_Common.hlsl"
static int Idle_NOTICE_MODE = 0;
static IdleNotice Idle_NOTICE = (IdleNotice)0;
// The quiet: while a viewer is there (and during the afterglow) no new condense or fly-by event starts; the ones already running
// finish. Idle_QWIN holds the two latest windows of world clock (from, until, from, until): an event whose start falls in one
// was skipped. Idle_QUIET (0 .. 1) calms the transfer, whose moves are permanent and so cannot be skipped.
static float Idle_QUIET = 0.0;
static float4 Idle_QWIN = float4(0.0, 0.0, 0.0, 0.0);

/// Hidden
bool Idle_Skipped(float start)
{
    return (start >= Idle_QWIN.x && start < Idle_QWIN.y) || (start >= Idle_QWIN.z && start < Idle_QWIN.w);
}

// Six ribbons in two roles (plus the foreground blobs, which are not ribbons):
//   A (0-1)  background: loose dust over the far background (Idle_FAR_DUST), or two dim fine sheets. They never trade particles.
//   B (2-5)  the story: four ribbons that trade particles. The one that takes them gets wider and brighter, the one that
//            gives them up thinner and dimmer.
// Per ribbon: depth of its middle and how far it drifts (and at what pace), height of its middle line above the horizon (at
// that depth), share of the particles, place in the palette, width / opacity / dot size / speed multipliers.
#define Idle_C0 2
#define Idle_NC 4
static const float Idle_ZC[Idle_RIBBONS] = { 17.0, 16.0, 4.0, 8.0, 5.0, 9.0 };
static const float Idle_ZA[Idle_RIBBONS] = { 1.0, 1.0, 4.0, 4.0, 4.0, 4.0 };
static const float Idle_ZP[Idle_RIBBONS] = { 3.0, 3.0, 1.0, 1.0, 1.0, 1.0 };
static const float Idle_RY[Idle_RIBBONS] = { 9.3, 12.8, 2.27, 5.55, 6.89, 10.9 };
static const float Idle_RW[Idle_RIBBONS] = { 5.0, 5.0, 9.0, 9.0, 9.0, 9.0 };
static const float Idle_RC[Idle_RIBBONS] = { 0.12, 0.22, 0.52, 0.8, 0.3, 0.95 };
static const float Idle_WM[Idle_RIBBONS] = { 3.0, 3.0, 1.0, 1.0, 1.0, 1.0 };
static const float Idle_AM[Idle_RIBBONS] = { 3.6, 3.6, 1.0, 1.0, 1.0, 1.0 };
static const float Idle_SM[Idle_RIBBONS] = { 3.0, 3.0, 1.0, 1.0, 1.0, 1.0 };
static const float Idle_SP[Idle_RIBBONS] = { 0.3, 0.3, 1.0, 1.0, 1.0, 1.0 };
#define Idle_RW_SUM 46.0

// ---- Evolution. Each event picks one ribbon and one kind of change over a stretch of it:
//   split  - the stretch forks into two branches that sway on their own; one swings back and overlaps the other;
//   gather - the stretch draws in toward its middle, denser and warmer, then lets go;
//   extend - some strands of the stretch sweep out in a new direction (any angle) and ease back.
// All of them are functions of (ribbon, u, strand, time): both ends of the stretch stay attached to the ribbon and every
// particle moves along a continuous path, so nothing resets. The stretch is fixed in the ribbon's own coordinates and
// particles keep flowing through it. Which strands take part is decided by the strand itself, along a wandering
// boundary, so changes peel strand by strand.
// 0 = the plain veil (A/B check).
#define Idle_EVOLVE 1
// Events running at once. Each extra one is the same schedule delayed by Idle_SLOT_PHASE seconds, with its own picks.
#define Idle_SLOTS 2
#define Idle_SLOT_PHASE 21.5
// Seconds. The first event starts at Idle_START, later ones a random 0..Idle_GAP_JIT after the quiet gap.
#define Idle_START 5.0
#define Idle_T_SPLIT 6.0
#define Idle_T_DRIFT 6.0
#define Idle_T_REUNITE 8.0
#define Idle_T_RELEASE 10.0
#define Idle_GAP_MIN 8.0
#define Idle_GAP_JIT 5.0
// Only these ribbons take part: ones high enough to stay clear of the horizon and big enough to read.
#define Idle_EVENT_RIBBONS 3
static const uint Idle_EVENT_R[Idle_EVENT_RIBBONS] = { 1, 3, 4 };
// Chances (out of 10) of split, and of split or gather; the rest is extend.
#define Idle_P_SPLIT 4
#define Idle_P_GATHER 7
// Length of the stretch (world units, along the ribbon).
#define Idle_SPAN 9.0
// How wide the transition between the strands that take part and the others is, in strand positions (-1..1), and how
// much the boundary wanders.
#define Idle_BLEND 0.45
#define Idle_WANDER 0.35
// Split: how much the returning branch overshoots the other one (1 = just meets, >1 = overlaps), sway of each branch, and
// how far the branches part in depth (fraction of the half-width).
#define Idle_MERGE 1.15
#define Idle_SWAY 0.35
#define Idle_DEPTH 0.35

// ---- Transfer. With Idle_TRANSFER 1 this runs instead of split / gather / extend. Every Idle_XINT seconds or so an event starts
// (they overlap): a stretch of one ribbon sends part of its particles to another ribbon, which is the one with fewer
// particles (and the sender is one with more). Each particle leaves at its own moment and flies along a bowed path, so the
// stretch thins out gradually and nothing opens up. The move is permanent: where a particle belongs is worked out by
// replaying every event so far (the schedule is deterministic), so there is no stored state. A ribbon's width follows the
// number of particles it holds. Ribbons also drift in depth on their own (Idle_Z0), so they swell and sink toward / away
// from the camera.
#define Idle_TRANSFER 1

struct IdleFx
{
    float dW;       // offset across the ribbon, world units
    float dN;       // offset through the ribbon
    float du;       // shift along the ribbon, in u
    float vs;       // scale of the strand position
    float glow;     // extra brightness
    float3 ext;     // offset in any direction (extend)
};

/// Hidden
uint Idle_Pcg(uint v)
{
    uint s = v * 747796405u + 2891336453u;
    uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
    return (w >> 22u) ^ w;
}

/// Hidden
float Idle_Rand(uint id, uint k)
{
    return (Idle_Pcg(id * 9781u + k * 6271u) & 0xFFFFFFu) / 16777216.0;
}

/// Hidden
float Idle_Z0(uint r, float age)
{
    // Depth of ribbon r's middle: a slow back-and-forth around its home depth, with its own pace and phase.
    uint k = r * 131u + 977u;
    float p = age / (Idle_ZPERIOD * Idle_ZP[r]);
    float a = Idle_TAU * (p * (0.8 + 0.4 * Idle_Rand(k, 1)) + Idle_Rand(k, 2));
    float b = Idle_TAU * (p * (1.9 + 0.6 * Idle_Rand(k, 3)) + Idle_Rand(k, 4));
    return Idle_ZC[r] + Idle_ZA[r] * (0.7 * sin(a) + 0.3 * sin(b));
}

/// Hidden
float3 Idle_Center(float u, uint r, float t, float zb)
{
    // Centerline of ribbon r at middle depth zb: a long irregular arc across the frame and beyond it. Its length and its height
    // above the horizon grow with the distance, so it covers the same part of the screen at any depth; only its size, haze
    // and brightness change.
    float s = lerp(0.9, 1.0, saturate(zb / 8.0));
    float k = zb - Idle_CAM_Z;
    float x = (u - 0.5) * 1.6 * k;
    float z = zb + 0.9 * s * sin(Idle_TAU * (0.8 * u + 0.3 * r + 0.04 * t));
    float ry = Idle_RY[r] * k / (Idle_ZC[r] - Idle_CAM_Z);
    float y = -Idle_SLOPE * (z - Idle_CAM_Z) + ry + s * (1.5 * sin(Idle_TAU * (0.55 * u + 0.17 * r + 0.05 * t))
                                                     + 0.6 * sin(Idle_TAU * (1.3 * u - 0.11 * t + 0.37 * r)));
    return float3(x, y, z);
}

/// Hidden
float3 Idle_Palette(float x)
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
float Idle_Line(float nx, float time)
{
    // Screen height (-1..1) of the horizon at screen x = nx.
    return Idle_HORIZON + Idle_WAVE * (0.6 * sin(2.1 * nx + 0.05 * time) + 0.4 * sin(5.3 * nx - 0.08 * time + 1.7));
}

/// Hidden
void Idle_Evolve(uint r, float u, float v, uint id, float h, float time, uint slot, inout IdleFx fx)
{
    // Adds the effect of the event running in `slot` on a particle of ribbon r at position u, strand v.
    const float total = Idle_T_SPLIT + Idle_T_DRIFT + Idle_T_REUNITE + Idle_T_RELEASE;
    const float cycle = total + Idle_GAP_MIN + Idle_GAP_JIT;
    float tt = time - slot * Idle_SLOT_PHASE;
    if (tt < 0.0) return;
    float k = floor(tt / cycle);
    uint seed = (uint)k * 31u + slot * 1013u + 7u;
    float e = tt - k * cycle - (k < 0.5 ? Idle_START : Idle_GAP_JIT * Idle_Rand(seed, 20));
    if (e <= 0.0 || e >= total) return;
    if (r != Idle_EVENT_R[(uint)(Idle_Rand(seed, 30) * Idle_EVENT_RIBBONS) % Idle_EVENT_RIBBONS]) return;
    uint kind = (uint)(Idle_Rand(seed, 40) * 10.0);

    // One curve per phase, so the phases overlap smoothly instead of switching.
    float open = smoothstep(0.0, Idle_T_SPLIT, e);
    float back = smoothstep(Idle_T_SPLIT + Idle_T_DRIFT, Idle_T_SPLIT + Idle_T_DRIFT + Idle_T_REUNITE, e);
    float release = smoothstep(total - Idle_T_RELEASE, total, e);
    float live = open * (1.0 - release);

    // The stretch grows from its middle; x runs 0..1 along it.
    float span = Idle_SPAN / (1.6 * (Idle_ZC[r] - Idle_CAM_Z));
    float uc = 0.5 + (Idle_Rand(seed, 31) - 0.5) * 0.3;
    float len = span * (0.35 + 0.65 * open);
    float x = (u - (uc - 0.5 * len)) / len;
    if (x <= 0.0 || x >= 1.0) return;

    // Which side of a wandering boundary this strand is on, softly: 0 .. 1.
    float sgn = Idle_Rand(seed, 32) < 0.5 ? -1.0 : 1.0;
    float q = sgn * (v + Idle_WANDER * sin(Idle_TAU * (1.7 * u + 0.9 * r + 0.03 * time)) + 0.15 * (Idle_Rand(id, 15) - 0.5));
    float b = 0.5 + 0.5 * tanh(q / Idle_BLEND);

    if (kind < Idle_P_SPLIT)
    {
        float g = pow(max(sin(3.14159 * x), 0.0), 1.5);
        float swayA = 1.0 + Idle_SWAY * sin(Idle_TAU * (0.9 * u + 0.045 * time + Idle_Rand(seed, 33)));
        float swayB = 1.0 + Idle_SWAY * sin(Idle_TAU * (0.9 * u - 0.060 * time + Idle_Rand(seed, 34)));
        float sideA = -open * swayA;
        float sideB = lerp(open * swayB, Idle_MERGE * sideA, back);
        float fade = g * (1.0 - release);
        fx.dW += lerp(sideA, sideB, b) * Idle_GAP * h * fade;
        fx.dN += (2.0 * b - 1.0) * open * (1.0 - back) * Idle_DEPTH * h * fade;
        fx.glow += Idle_GLOW * fade * open;
    }
    else if (kind < Idle_P_GATHER)
    {
        // Draw in toward the middle (along and across), slowly breathing. The pull stays below 1 so the mapping never folds.
        float w = 0.5 + 0.5 * cos(3.14159 * (2.0 * x - 1.0));
        float pull = min(Idle_GATHER, 0.9) * live * (1.0 + 0.12 * sin(Idle_TAU * (0.11 * time + Idle_Rand(seed, 35))));
        fx.du += pull * (uc - u) * w;
        fx.vs *= 1.0 - 0.55 * w * live;
        fx.glow += Idle_GLOW * w * live;
    }
    else
    {
        // Some strands sweep out in a new direction; slow to rise, quicker to come back. Zero at both ends.
        float a = Idle_TAU * Idle_Rand(seed, 41);
        float3 dir = float3(cos(a), sin(a), 0.6 * (Idle_Rand(seed, 42) - 0.5));
        float prof = x * sqrt(max(1.0 - x, 0.0)) / 0.385;
        float sel = smoothstep(0.1, 0.6, 1.0 - b);
        fx.ext += dir * (Idle_EXTEND * live * prof * sel);
        fx.glow += Idle_GLOW * 0.6 * live * prof * sel;
    }
}

struct IdlePt
{
    float3 pos;
    float hue;
};

/// Hidden
IdlePt Idle_At(uint r, float u, float v, uint id, float age, float ws, IdleFx fx)
{
    // Where the particle (u along, v across) sits when it belongs to ribbon r; ws scales the ribbon's width.
    float t = age * Idle_MOTION * Idle_SP[r];
    float zb = Idle_Z0(r, age);
    float s = lerp(0.9, 1.0, saturate(zb / 8.0));
    float ue = u + fx.du;
    float3 c = Idle_Center(ue, r, t, zb);
    float3 T = normalize(Idle_Center(ue + 0.01, r, t, zb) - Idle_Center(ue - 0.01, r, t, zb));
    float3 A = normalize(cross(T, float3(0, 0, 1)));
    float3 B = cross(T, A);
    float phi = Idle_TAU * (Idle_TWIST * ue + 0.2 * r + 0.06 * t);
    float3 W = cos(phi) * A + sin(phi) * B;
    float3 N = cross(T, W);
    float pinch = 0.5 + 0.5 * sin(Idle_TAU * (1.1 * ue + 0.23 * r - 0.07 * t));
    float h = Idle_WIDTH * s * ws * Idle_WM[r] * (0.3 + 0.7 * pinch);
    IdlePt p;
    p.pos = c + W * (v * fx.vs * h + fx.dW) + N * ((Idle_Rand(id, 5) - 0.5) * Idle_THICK * s + fx.dN) + fx.ext;
    p.hue = 0.5 + (Idle_RC[r] - 0.5) * Idle_COLOR_SPREAD + Idle_COLOR_SHIFT
          + 0.16 * sin(Idle_TAU * (0.7 * u + 0.04 * t + 0.21 * r));
    return p;
}

struct IdleHop
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
IdleHop Idle_Track(uint id, uint r0, float time, float v, float u)
{
    // Replays every transfer event up to now for this particle. Event j starts at a jittered multiple of Idle_XINT (the
    // jitter is smaller than the interval, so events stay in order) and lasts Idle_XDUR. The expected number of particles on
    // each ribbon (nl, at the end of every event; nv, as the events progress) steers which ribbon gives and which takes.
    const float D0 = Idle_XDUR;
    IdleHop h;
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
    if (r0 < Idle_C0) return h;      // only the event ribbons trade
    float nl[Idle_RIBBONS];
    float nv[Idle_RIBBONS];
    for (uint i = 0; i < Idle_RIBBONS; i++)
    {
        nl[i] = Idle_RW[i] / Idle_RW_SUM;
        nv[i] = nl[i];
    }
    float tau = -1.0;           // when the particle's latest move starts
    float tr = 1.0;             // how long that flight takes
    float lastArrive = -1.0;
    uint lastDst = 99u;
    uint jmax = (uint)(time / Idle_XINT) + 1u;
    [loop]
    for (uint j = 0; j <= jmax; j++)
    {
        uint seed = j * 7919u + 101u + Idle_RS;
        float D = D0 * (0.65 + 0.7 * Idle_Rand(seed, 10));       // each event runs at its own length
        // Event j starts somewhere in its own slot, early enough to be over before the next slot begins: events never overlap
        // (as long as Idle_XDUR is shorter than Idle_XINT), whatever the run seed.
        float start = Idle_XINT * (j + 0.3) + max(0.0, Idle_XINT - D) * Idle_Rand(seed, 1);
        if (start > time) break;

        // Who gives and who takes: of two random event ribbons the fuller one gives, and it hands over to the emptier of its
        // neighbours (mostly the next one, sometimes the one after), so the flight is short and reads as a bridge.
        uint a1 = Idle_C0 + (uint)(Idle_Rand(seed, 2) * Idle_NC) % Idle_NC;
        uint a2 = Idle_C0 + (uint)(Idle_Rand(seed, 3) * Idle_NC) % Idle_NC;
        // Whoever received last time is not the giver this time, so a ribbon is never still glowing from taking when it
        // starts to give.
        if (a1 == lastDst) a1 = Idle_C0 + (a1 - Idle_C0 + 1u) % Idle_NC;
        if (a2 == lastDst) a2 = Idle_C0 + (a2 - Idle_C0 + 1u) % Idle_NC;
        uint src = nl[a1] >= nl[a2] ? a1 : a2;
        // The receiver is the emptier of two random candidates, never the giver and never the one that received last time, so
        // the taking rotates around the ribbons instead of piling up on one.
        uint c1 = Idle_C0 + (uint)(Idle_Rand(seed, 11) * Idle_NC) % Idle_NC;
        uint c2 = Idle_C0 + (uint)(Idle_Rand(seed, 12) * Idle_NC) % Idle_NC;
        for (uint k = 0; k < 3; k++)
        {
            if (c1 == src || c1 == lastDst) c1 = Idle_C0 + (c1 - Idle_C0 + 1u) % Idle_NC;
            if (c2 == src || c2 == lastDst) c2 = Idle_C0 + (c2 - Idle_C0 + 1u) % Idle_NC;
        }
        uint dst = nl[c1] <= nl[c2] ? c1 : c2;
        lastDst = dst;

        // The stretch (in u) and how many of its particles go. The edge of the stretch is soft.
        float span = 0.4 + 0.3 * Idle_Rand(seed, 7);
        // Each event leans one way: 0 side shift (crosses over, a little lean), 1 seep (leaves from one side of the strands,
        // few and slow), 2 lopsided pile (lands on one side of the receiver).
        const float AMT[3] = { 1.0, 0.6, 0.85 };
        const float SIDE[3] = { 0.2, 0.9, 0.5 };
        const float LEAN[3] = { 0.25, 0.1, 0.6 };
        const float BOW[3] = { 0.16, 0.06, 0.1 };
        uint tend = (uint)(Idle_Rand(seed, 60) * 3.0) % 3u;
        float sgn = Idle_Rand(seed, 61) < 0.5 ? -1.0 : 1.0;
        float dirU = Idle_Rand(seed, 62) < 0.5 ? -1.0 : 1.0;
        float share = saturate(Idle_XAMT * (0.7 + 0.3 * Idle_Rand(seed, 8)) * AMT[tend]);
        float uc = 0.5 + (Idle_Rand(seed, 9) - 0.5) * 0.4;
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
        float us = frac(Idle_Rand(id, 1) + start * Idle_FLOW * (0.5 + Idle_Rand(id, 2)));
        float e = abs(us - uc) / (0.5 * span);
        float gu = exp(-4.0 * e * e);
        if (h.cur == dst)
            h.hlD = max(h.hlD, 0.45 * gu * smoothstep(start + 0.3 * D, start + 0.8 * D, time) * (1.0 - smoothstep(start + 1.3 * D, start + 1.6 * D, time)));
        if (h.cur != src) continue;
        float sideW = lerp(1.0, smoothstep(-0.8, 0.8, sgn * v), SIDE[tend]);
        if (Idle_Rand(id + seed * 7919u, 57) > share * exp(-2.5 * e * e) * sideW)
        {
            h.hlS = max(h.hlS, 0.25 * gu * smoothstep(start, start + 0.4 * D, time) * (1.0 - smoothstep(start + 0.7 * D, start + 1.0 * D, time)));
            continue;
        }
        // Departures sweep along the stretch like a front.
        float sweep = saturate(0.5 + 0.5 * dirU * (us - uc) / (0.5 * span));
        float t2 = start + D * (0.25 + 0.4 * sweep + 0.1 * Idle_Rand(id + seed * 131u, 50));   // never before start + 0.25 D: the glow ramp ahead of it must fit inside the event
        if (t2 < lastArrive) continue;
        float trl = D * (0.3 + 0.1 * Idle_Rand(id + seed * 131u, 51)) * (tend == 1u ? 1.25 : 1.0);
        // This particle's glow in this event: it ramps up (twinkling) before it goes and lets go as it flies; the landing
        // flares and holds until the last arrival. A particle that has not gone yet keeps its earlier move and earlier glow
        // untouched, so nothing it already had is dropped when the next event starts.
        h.hlS = max(h.hlS, smoothstep(t2 - 0.25 * D, t2 - 0.02 * D, time) * (1.0 - smoothstep(t2, t2 + 0.15 * trl, time)));
        if (t2 > time) continue;
        h.hlD = max(h.hlD, smoothstep(t2 + 0.5 * trl, t2 + trl, time) * (1.0 - smoothstep(start + 1.3 * D, start + 1.6 * D, time)));
        tau = t2;
        tr = trl;
        h.bow = sgn * BOW[tend] * (0.5 + 0.5 * Idle_Rand(seed, 63));
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
    float rc = max(nv[h.cur] * Idle_RW_SUM / Idle_RW[h.cur], 0.05);
    float rp = max(nv[h.prev] * Idle_RW_SUM / Idle_RW[h.prev], 0.05);
    h.wsCur = clamp(1.0 + Idle_WFOLLOW * (rc - 1.0), 0.4, 2.2);
    h.wsPrev = clamp(1.0 + Idle_WFOLLOW * (rp - 1.0), 0.4, 2.2);
    h.brCur = clamp(1.0 + Idle_GLOW * (rc - 1.0), 0.3, 2.5);
    h.brPrev = clamp(1.0 + Idle_GLOW * (rp - 1.0), 0.3, 2.5);
    return h;
}

// ---- Condense. Every Idle_CINT seconds a stretch of one B ribbon draws in dust from the far background around it: dust
// near the stretch is the likeliest to be taken (Idle_CSHARE at its peak, falling off over Idle_CREACH screen heights), each
// particle flies in at its own moment, speeding up as it nears, stays part of the ribbon for a while, then breathes out and
// settles back where it was, slowing down. Like the transfer, it is a function of (particle, time) with no stored state.
// The ribbon's own particles in the stretch brighten faintly while it takes the dust in; the dust that has landed glows.
#define Idle_CINT 60.0
#define Idle_CDUR 34.0
#define Idle_CSTART 20.0
#define Idle_CSHARE 1.6      // chance scale; the chance is this times the falloff, capped at 1
#define Idle_CREACH 1.2      // how far from the stretch dust is still taken from, in screen heights

struct IdleCd
{
    bool on;        // an event has started (its tail is part of it)
    float sk;       // when it started
    uint rr;        // the ribbon that takes the dust in
    float uc;       // middle of its stretch, in u
    float span;     // length of the stretch, in u
    uint cs;        // seed of the event
};

/// Hidden
IdleCd Idle_Cond(float age)
{
    IdleCd c;
    c.on = false;
    c.sk = 0.0;
    c.rr = Idle_C0;
    c.uc = 0.5;
    c.span = 0.5;
    c.cs = 0u;
    float tc = age - Idle_CSTART;
    if (tc < 0.0) return c;
    float ck = floor(tc / Idle_CINT);
    c.cs = (uint)ck * 6151u + 313u + Idle_RS;
    c.sk = Idle_CSTART + ck * Idle_CINT + (Idle_CINT - Idle_CDUR - 2.0) * Idle_Rand(c.cs, 1);   // always inside its own slot
    c.rr = Idle_C0 + (uint)(Idle_Rand(c.cs, 2) * Idle_NC) % Idle_NC;
    c.uc = 0.5 + (Idle_Rand(c.cs, 3) - 0.5) * 0.4;
    c.span = 0.4 + 0.2 * Idle_Rand(c.cs, 4);
    c.on = age >= c.sk && !Idle_Skipped(c.sk);
    return c;
}

// ---- Fly-by. Its own VFX (Idle_Fly.vfx, entry IdleFly, a soft Gaussian sprite instead of the shared dot, so it can blur
// for real). Every Idle_FINT seconds Idle_FN particles come out of the far background toward the lens, each at its own
// moment: they idle, then speed up hard as they near, and grow with the perspective into one big soft out-of-focus glow,
// getting paler and then dazzling as they pass the lens. A flight keeps its place in the world, so the perspective carries
// it past the frame's edge, where it fades. A side show, never in the mirror.
#define Idle_FINT 45.0
#define Idle_FDUR 16.0       // from the first particle leaving to the last one gone
#define Idle_FSTART 25.0
#define Idle_FN 40u          // flights per event (= the particle capacity of Idle_Fly.vfx)
#define Idle_FSLOW 6.0       // how long a flight idles before it rushes: higher = slower start, faster end
#define Idle_FGLARE 5.0      // how much brighter it gets as it passes the lens
#define Idle_FSIZE 30.0      // extra growth of the glow at the end of the flight

struct IdleFl
{
    bool on;
    float sk;
    uint cs;
};

/// Hidden
IdleFl Idle_Fly(float age)
{
    IdleFl c;
    c.on = false;
    c.sk = 0.0;
    c.cs = 0u;
    float tc = age - Idle_FSTART;
    if (tc < 0.0) return c;
    float ck = floor(tc / Idle_FINT);
    c.cs = (uint)ck * 4421u + 977u + Idle_RS;
    c.sk = Idle_FSTART + ck * Idle_FINT + (Idle_FINT - Idle_FDUR - 6.0) * Idle_Rand(c.cs, 1);   // its tail ends inside its own slot
    c.on = age >= c.sk && !Idle_Skipped(c.sk);
    return c;
}

#include "Assets/_Project/Notice/Notice_Pulse.hlsl"
#include "Assets/_Project/Notice/Notice_Focus.hlsl"
#include "Assets/_Project/Notice/Notice_Clear.hlsl"
#include "Assets/_Project/Notice/Notice_Flow.hlsl"

/// Hidden
void Idle_NoticeBody(inout float3 pos, inout float3 color, inout float alpha, inout float sizeMul,
                     uint id, uint ribbon, float u, bool dust)
{
    Notice_Body(pos, color, alpha, sizeMul, id, ribbon, u, dust, Idle_NOTICE, Idle_NOTICE_MODE);
}

// noticeOff, noticeVel: the dot's stored flow offset and its speed (the entry points load and save the attributes, so the effects
// that do not store them never see them). noticeDt: seconds since this effect's last update.
/// Hidden
void Idle_Core(inout VFXAttributes attributes, bool mirror, inout float2 noticeOff, inout float2 noticeVel, float noticeDt)
{
    uint id = attributes.particleId;
    float t = attributes.age * Idle_MOTION;

    // The horizon line: particles on it at every distance, spread across the frame, a few pixels thick, brighter in
    // patches that drift along it.
    if (Idle_Rand(id, 8) < Idle_LINE_SHARE)
    {
        float z = 10.0 + 600.0 * pow(Idle_Rand(id, 11), 1.6);
        float d = z - Idle_CAM_Z;
        float nx = (Idle_Rand(id, 10) - 0.5) * 2.1;
        float sd = Idle_Rand(id, 12) * Idle_Rand(id, 12) * Idle_LINE_THICK * d * Idle_TANH;
        float3 p = float3(nx * d * Idle_TANH * 2.0, Idle_Line(nx, attributes.age) * d * Idle_TANH + sd, z);
        float patch = 0.5 + 0.5 * sin(6.3 * nx + 0.2 * attributes.age) * sin(2.7 * nx - 0.13 * attributes.age + 0.8);
        attributes.position = p;
        attributes.color = Idle_Palette(0.05 + 0.3 * Idle_Rand(id, 13)) * Idle_BRIGHT;
        attributes.alpha = mirror ? 0.0 : Idle_LINE_ALPHA * (0.4 + 0.6 * Idle_Rand(id, 14)) * (0.25 + 1.5 * patch);
        attributes.size = 0.0013 * d;
        return;
    }

    // Pick a ribbon by its share of the particles.
    float pick = Idle_Rand(id, 0) * Idle_RW_SUM;
    uint r = 0;
    for (; r < Idle_RIBBONS - 1; r++)
    {
        if (pick < Idle_RW[r]) break;
        pick -= Idle_RW[r];
    }
    float u = frac(Idle_Rand(id, 1) + attributes.age * Idle_FLOW * Idle_SP[r] * (0.5 + Idle_Rand(id, 2)));
    float halo = Idle_HALO * pow(Idle_Rand(id, 9), 6.0);
    // Strands: 24 of them, but unevenly spaced, so they never line up into a regular hatching.
    float si = floor(Idle_Rand(id, 3) * 24.0);
    float sc = si + 0.5 + 0.8 * (Idle_Rand(r * 31u + (uint)si, 74) - 0.5);
    float v = ((sc + 0.5 * (Idle_Rand(id, 4) - 0.5)) / 24.0) * 2.0 - 1.0;
    v *= 1.0 + halo;

    IdleFx fx;
    fx.dW = 0.0;
    fx.dN = 0.0;
    fx.du = 0.0;
    fx.vs = 1.0;
    fx.glow = 0.0;
    fx.ext = 0.0;
#if Idle_EVOLVE && !Idle_TRANSFER
    float s0 = lerp(0.9, 1.0, saturate(Idle_Z0(r, attributes.age) / 8.0));
    float h0 = Idle_WIDTH * s0 * (0.3 + 0.7 * (0.5 + 0.5 * sin(Idle_TAU * (1.1 * u + 0.23 * r - 0.07 * t))));
    for (uint e = 0; e < Idle_SLOTS; e++)
        Idle_Evolve(r, u, v, id, h0, attributes.age, e, fx);
#endif

    // Which ribbon it is on now (and, while it flies, which one it left), then where it sits.
    uint rc = r;
    uint rp = r;
    float away = 1.0;
    float wc = 1.0;
    float wp = 1.0;
    float bc = 1.0;
    float bp = 1.0;
#if Idle_TRANSFER
    IdleHop hop = Idle_Track(id, r, attributes.age, v, u);
    rc = hop.cur;
    rp = hop.prev;
    away = hop.away;
    wc = hop.wsCur;
    wp = hop.wsPrev;
    bc = hop.brCur;
    bp = hop.brPrev;
    wc = lerp(wc, 1.0, Idle_QUIET);
    wp = lerp(wp, 1.0, Idle_QUIET);
    bc = lerp(bc, 1.0, Idle_QUIET);
    bp = lerp(bp, 1.0, Idle_QUIET);
    // A particle that has moved leans toward one side of its new strands and has drifted downstream.
    float v2 = v;
    IdleFx fxa = fx;
    if (hop.moved)
    {
        v2 = lerp(v, hop.sgn * (0.35 + 0.45 * abs(v)), hop.lean * away);
        fxa.du += hop.dU * away;
    }
#else
    float v2 = v;
    IdleFx fxa = fx;
#endif
    IdlePt a = Idle_At(rc, u, v2, id, attributes.age, wc, fxa);
    float3 pos = a.pos;
    float hue = a.hue;
    float moving = 0.0;
    float br = bc;
    if (rp != rc)
    {
        // In flight: from where it was on the old ribbon to where it will be on the new one, bowing to one side so the
        // particles fan out instead of running in parallel lines.
        IdlePt b = Idle_At(rp, u, v, id, attributes.age, wp, fx);
        float3 delta = a.pos - b.pos;
        float2 side = normalize(float2(-delta.y, delta.x) + 1e-5);
        pos = lerp(b.pos, a.pos, away);
        pos.xy += side * (length(delta) * sin(3.14159 * away) * (hop.bow + 0.04 * (2.0 * Idle_Rand(id, 45) - 1.0)));
        hue = lerp(b.hue, a.hue, away);
        moving = sin(3.14159 * away) * (1.0 - Idle_QUIET);
        br = lerp(bp, bc, away);
    }

    float amx = Idle_AM[r];
    float smx = Idle_SM[r];
    float uFade = 1.0;
    float cw = 0.0;         // 0 .. 1: how far a dust particle has joined a ribbon
    float cglow = 0.0;
    float cglowS = 0.0;
    bool dust = Idle_FAR_DUST && r < 2u;
    if (dust)
    {
        // Uniform spots over the far frustum, bent by two slow low-frequency waves so the density varies (the bend is mild
        // enough not to fold, so no hard clumps). Always above the horizon line.
        float sx = Idle_Rand(id, 70) * 2.0 - 1.0;
        float sy = Idle_Rand(id, 71) * 2.0 - 1.0;
        float ph = Idle_Rand(r, 72);
        float nx = sx + 0.12 * sin(Idle_TAU * (0.6 * sy + 0.012 * attributes.age + ph))
                      + 0.06 * sin(Idle_TAU * (1.3 * sy - 0.02 * attributes.age + 2.0 * ph));
        float ny = sy + 0.15 * sin(Idle_TAU * (0.5 * sx + 0.015 * attributes.age + 3.0 * ph));
        float z = 17.0 + 13.0 * Idle_Rand(id, 73);
        float dd = z - Idle_CAM_Z;
        float scr = lerp(Idle_Line(nx, attributes.age), 1.05, saturate(0.5 + 0.5 * ny));
        pos = float3(nx * dd * Idle_TANH * 2.0 * 1.05, scr * dd * Idle_TANH, z);

        // Condense: if this particle is one of the dust the running event draws in, it flies to the stretch and back.
        IdleCd cdd = Idle_Cond(attributes.age);
        bool taken = false;
        if (cdd.on)
        {
            // Dust whose landing spot is near its own place is the likeliest to be taken; the landing is fixed at the event's
            // start so the choice never changes mid-event.
            float u0 = cdd.uc + (Idle_Rand(id, 58) - 0.5) * cdd.span;
            float3 cc = Idle_Center(u0, cdd.rr, cdd.sk * Idle_MOTION * Idle_SP[cdd.rr], Idle_Z0(cdd.rr, cdd.sk));
            float2 ds = pos.xy / (dd * Idle_TANH) - cc.xy / ((cc.z - Idle_CAM_Z) * Idle_TANH);
            taken = Idle_Rand(id + cdd.cs * 7919u, 57) < Idle_CSHARE * exp(-dot(ds, ds) / (Idle_CREACH * Idle_CREACH));
        }
        if (taken)
        {
            float age = attributes.age;
            float ts = cdd.sk + Idle_CDUR * (0.04 + 0.26 * Idle_Rand(id + cdd.cs * 131u, 50));
            float tin = Idle_CDUR * 0.2;
            float tl = cdd.sk + Idle_CDUR * (0.72 + 0.12 * Idle_Rand(id + cdd.cs * 131u, 51));   // it stays a good while
            float tout = Idle_CDUR * 0.2;
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
                float uL = frac(cdd.uc + (Idle_Rand(id, 58) - 0.5) * cdd.span + (age - cdd.sk) * Idle_FLOW * Idle_SP[cdd.rr] * (0.5 + Idle_Rand(id, 2)));
                IdlePt lp = Idle_At(cdd.rr, uL, v, id, age, 1.0, fx);
                float3 dl = lp.pos - pos;
                float2 sdir = normalize(float2(-dl.y, dl.x) + 1e-5);
                float bowSgn = Idle_Rand(cdd.cs, 5) < 0.5 ? -1.0 : 1.0;
                float3 p0 = pos;
                pos = lerp(p0, lp.pos, cwp);
                pos.xy += sdir * (length(dl) * cbow * sin(3.14159 * cwp) * bowSgn * (0.5 + 0.5 * Idle_Rand(id, 45)));
                hue = lerp(hue, lp.hue, cw);
                amx = lerp(amx, Idle_AM[cdd.rr], cw);
                smx = lerp(smx, Idle_SM[cdd.rr], cw);
                uFade = lerp(1.0, smoothstep(0.0, 0.12, uL) * smoothstep(1.0, 0.88, uL), cw);
            }
        }
    }
    float f = saturate(pos.z / Idle_DEPTH_Z);
    float fade = dust ? uFade : smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.88, u);
    float alpha = Idle_ALPHA * fade * (0.6 + 0.4 * Idle_Rand(id, 6)) * (1.0 - 0.5 * saturate(halo / Idle_HALO))
                * lerp(1.0, Idle_FAR_ALPHA, f) * (1.0 + fx.glow) * (1.0 + 1.2 * moving) * br * amx;

    // Color: each ribbon has its own place in the palette, drifting slowly along its length; far things fade into the fog
    // color; the active stretch of an event turns toward a warm white.
    float3 color = lerp(Idle_Palette(hue), Idle_FOG_COLOR, Idle_FOG * f * (r < 2u ? 0.4 : 1.0));   // the far sheets keep most of their color
    if (dust) color = lerp(color, dot(color, float3(0.3, 0.59, 0.11)).xxx, 0.6 * (1.0 - cw));   // the far dust stays quiet: much less saturated
    color = lerp(color, float3(1.0, 0.80, 0.55), saturate(fx.glow * 0.5));
    color = lerp(color, float3(1.0, 0.85, 0.60), 0.35 * moving);   // particles in flight are brighter and warmer

    float hlS = 0.0;
    float hlD = 0.0;
#if Idle_TRANSFER
    hlS = hop.hlS * (1.0 - Idle_QUIET);
    hlD = hop.hlD * (1.0 - Idle_QUIET);
#endif
    // The dust that has landed in a condensing stretch glows, and so does the ribbon's own part of that stretch.
    hlD = max(hlD, cglow);
    hlS = max(hlS, cglowS);
    IdleCd cd = Idle_Cond(attributes.age);
    if (cd.on && !dust && rc == cd.rr)
    {
        float cu = frac(Idle_Rand(id, 1) + cd.sk * Idle_FLOW * (0.5 + Idle_Rand(id, 2)));
        float cg = abs(cu - cd.uc) / (0.5 * cd.span);
        hlD = max(hlD, 0.4 * exp(-4.0 * cg * cg) * smoothstep(cd.sk + 0.15 * Idle_CDUR, cd.sk + 0.35 * Idle_CDUR, attributes.age)
                       * (1.0 - smoothstep(cd.sk + 0.8 * Idle_CDUR, cd.sk + Idle_CDUR, attributes.age)));
    }
    // Shine: the same hue, brighter and a little bigger. The giver twinkles as its particles get ready to leave, the receiver
    // glows steadily. Only a faint tint, so the colors stay.
    float twinkle = pow(0.5 + 0.5 * sin(Idle_TAU * (0.9 * attributes.age * (0.5 + Idle_Rand(id, 80)) + Idle_Rand(id, 81))), 4.0);
    float shine = hlD + hlS * (0.35 + 1.3 * twinkle);
    alpha *= 1.0 + Idle_HL * shine;
    color *= 1.0 + 0.8 * shine;
    color = lerp(color, float3(0.75, 0.88, 1.0), 0.12 * hlS);
    color = lerp(color, float3(1.0, 0.82, 0.55), 0.12 * hlD);

    // The world noticing a viewer: reshapes the particle in the world, so its reflection follows. Flow bends the dots around the
    // viewer and remembers how far; the other parts are worked out fresh every frame, so the remembered offset is let go.
    float sizeMul = 1.0;
    if ((Idle_NOTICE_MODE & Notice_PARTS_FLOW) != 0)
        Notice_Flow(pos, noticeOff, noticeVel, id, rc, u, dust, Idle_NOTICE, Idle_NOTICE_MODE, noticeDt);
    else
    {
        noticeOff = 0.0;
        noticeVel = 0.0;
        Idle_NoticeBody(pos, color, alpha, sizeMul, id, rc, u, dust);
    }

    // Never below the horizon: what would sink is eased onto the line and fades, so it piles up as a soft contact edge.
    float d = pos.z - Idle_CAM_Z;
    float lineY = Idle_Line(pos.x / (d * Idle_TANH * 2.0), attributes.age) * d * Idle_TANH;   // the line, at this depth
    float sd = pos.y - lineY;
    if (sd < Idle_MARGIN)
    {
        float sd2 = Idle_MARGIN * exp((sd - Idle_MARGIN) / Idle_MARGIN);
        alpha *= exp(-0.6 * (Idle_MARGIN - sd) / Idle_MARGIN);
        pos.y += sd2 - sd;
        sd = sd2;
    }
    if (mirror)
    {
        // The same particle flipped about the line: dimmer, bluer, rippling a little, fainter the higher the original is.
        pos.y = lineY - sd * Idle_REFL_SQUASH;
        pos.x += Idle_RIPPLE * sd * sin(1.7 * sd - attributes.age * 0.6 + pos.x * 0.3);
        alpha *= Idle_REFL * exp(-sd / Idle_REFL_FADE);
        color = lerp(color, Idle_FOG_COLOR, 0.35);
    }

    attributes.position = pos;
    attributes.color = color * Idle_BRIGHT;
    attributes.alpha = alpha;
    attributes.size = Idle_SIZE * lerp(Idle_NEAR_SIZE, Idle_FAR_SIZE, f) * smx * (1.0 + 0.25 * moving) * (1.0 + 0.5 * shine) * (0.7 + 0.6 * Idle_Rand(id, 7)) * sizeMul;
}

/// Hidden
void Idle_FlyCore(inout VFXAttributes attributes)
{
    attributes.position = float3(0.0, 0.0, 0.0);
    attributes.color = float3(0.0, 0.0, 0.0);
    attributes.alpha = 0.0;
    attributes.size = 0.0;
    uint id = attributes.particleId;
    if (id >= Idle_FN) return;
    IdleFl fl = Idle_Fly(attributes.age);
    if (!fl.on) return;
    uint fs = fl.cs * 131u + id * 977u;
    float flyT = 4.0 + 1.5 * Idle_Rand(fs, 60);
    float tS = fl.sk + (Idle_FDUR - flyT) * Idle_Rand(fs, 61);
    float pf = (attributes.age - tS) / flyT;
    if (pf <= 0.0 || pf >= 1.0) return;
    // Where it sits on screen at the start (in screen half-heights), never in the middle; and how far away it starts.
    float2 s0 = float2((Idle_Rand(fs, 62) * 2.0 - 1.0) * 1.9, lerp(-0.7, 0.95, Idle_Rand(fs, 63)));
    s0 *= max(1.0, 0.55 / max(length(s0), 1e-3));
    float dd = 31.0 + 13.0 * Idle_Rand(fs, 64);
    // The flight is driven by how far it has grown on screen, so the speed across the frame keeps climbing until it leaves:
    // it starts at its place and ends 1.5 frame-edges out. Perspective then puts it that much closer to the lens.
    float e = pow(pf, Idle_FSLOW);
    float edge0 = max(abs(s0.x) * 0.5, abs(s0.y));             // 1 = at the frame's edge
    float S = 1.0 + (1.5 / edge0 - 1.0) * e;
    float dn = dd / S;
    float3 pos = float3(s0 * dd * Idle_TANH, Idle_CAM_Z + dn);   // keeps its sideways place in the world
    float edge = edge0 * S;
    float fb = smoothstep(0.1, 0.8, e);                        // how far it has come
    float fc = smoothstep(0.1, 0.9, pf);                       // how pale
    float fg = smoothstep(0.5, 0.95, e);                       // the dazzle
    float f = saturate(pos.z / Idle_DEPTH_Z);
    float vis = smoothstep(0.0, 0.12, pf) * (1.0 - smoothstep(1.05, 1.4, edge));
    float3 color = lerp(Idle_Palette(0.1 + 0.85 * Idle_Rand(fs, 65)), Idle_FOG_COLOR, Idle_FOG * f * 0.4);
    color = lerp(color, dot(color, float3(0.3, 0.59, 0.11)).xxx, 0.6 * (1.0 - fb));   // quiet when far, colorful when near
    color = lerp(color, float3(0.95, 0.97, 1.0), 0.1 * fc);   // stays colored; the glow comes from the soft sprite
    color *= 1.0 + 0.8 * fg;
    attributes.position = pos;
    attributes.color = color * Idle_BRIGHT;
    attributes.alpha = Idle_ALPHA * 3.6 * (0.6 + 0.4 * Idle_Rand(fs, 66)) * lerp(1.0, Idle_FAR_ALPHA, f) * vis * (1.0 + 0.5 * Idle_FGLARE * fg);
    attributes.size = Idle_SIZE * lerp(Idle_NEAR_SIZE, Idle_FAR_SIZE, f) * 3.0 * (1.0 + Idle_FSIZE * fb) * (0.7 + 0.6 * Idle_Rand(fs, 67));
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
/// noticeMode: Which parts of the reaction to a viewer are on, as a bit mask: 1 clear, 2 pulse, 4 focus, 8 flow (instead of the other three; 16 and 32 are test switches). 0 = none (the plain idle). Set by NoticeSensor.
/// noticeClock: The world's clock in seconds, used instead of the particle age while a mode is on; it runs slow during the hush. Set by NoticeSensor.
/// noticeStay: 0 - 1, how far the world is into the stay stage. Set by NoticeSensor.
/// noticeLong: 0 - 1, how far the world is into the long-stay stage. Set by NoticeSensor.
/// noticeViewerX: Screen x of the viewer, -1 - 1, smoothed so it trails. Set by NoticeSensor.
/// noticeViewerY: Screen y of the viewer, -1 - 1, smoothed the same way. Set by NoticeSensor.
/// noticeQuiet: 0 - 1, how quiet the world is while a viewer is there. Calms the transfer. Set by NoticeSensor.
/// noticeQuietFrom: Start (world clock) of the latest quiet window: events that would start inside it are skipped. Set by NoticeSensor.
/// noticeQuietUntil: End of the latest quiet window (a huge number while it lasts). Set by NoticeSensor.
/// noticeQuietFrom2: Start of the window before that. Set by NoticeSensor.
/// noticeQuietUntil2: End of the window before that. Set by NoticeSensor.
/// noticeWidthStay: Half the width of the space the world clears for a viewer after a stay (3 - 10 s), in screen half-heights. The viewer's box in the Game view is 0.18 wide.
/// noticeWidthLong: Half the width after a long stay (over 10 s).
/// noticeHeightStay: Half the height of the cleared space after a stay. The viewer's box is 0.63 tall.
/// noticeHeightLong: Half the height after a long stay.
/// noticeRim: How soft the pile-up on the rim is. Smaller = a wider, softer, more gradual squeeze that bends the ribbons around the space from further away; bigger = a thin hard edge. Clamped to 0.05 - 0.8; about 0.25 reads best.
/// noticeRimEven: How much of the pile-up's extra brightness is cancelled. 0 = a very bright rim, 1 = no glow at all.
/// noticeRagged: How far the edge of the space is bent out of straight, in screen half-heights. 0 = a plain capsule, bigger = a more ragged, wavy edge.
/// noticeWidthWobble: How much the width changes from the top of the space to the bottom (share of the width). 0 = straight sides.
/// noticeTilt: How far the whole space sways to one side and the other, in radians. 0 = always upright.
/// noticeOrbitStay: Share of the dots near the space that leave their ribbons and circle it, after a stay.
/// noticeOrbitLong: The same after a long stay.
/// noticeReachStay: How far from the edge (screen half-heights) a dot can be and still be drawn into orbit, after a stay.
/// noticeReachLong: The same after a long stay.
/// noticeInside: Share of the orbiting dots that are allowed to dip inside the space now and then. Keep it tiny (0.003) or the inside is not empty.
/// noticePulseSweep: Seconds the bright ring takes to come in toward the viewer. Smaller = faster.
/// noticePulseStop: Where the bright ring stops, in steps outside the rim (1 step = 0.35 screen half-heights). About 1.6 is the outer edge of the dots the viewer has pushed aside; bigger = it stops further away.
/// noticeWakeX: Screen x, -1 - 1, of a slower shadow of the viewer. The stretch from the viewer back to it is the tail the field drags behind a moving viewer. Set by NoticeSensor.
/// noticeWakeY: Screen y of that slower shadow. Set by NoticeSensor.
/// noticeCoreKeep: Share of the dots that do not leave the middle of the core, dimmer and smaller the closer to the middle line they are (the far layers keep 3 times as many). The core is already thin on its own, a ramp that is empty on the middle line and full at the edge; this adds a few dots on top. 0 = just the ramp.
/// noticeDeflect: How far the dots slide along the capsule instead of straight out, as a share of how far they are pushed out. 0 = straight out like a wall; 0.6 = about 30 degrees; above 1 = more sliding than pushing. Clamped to 0 - 1.5.
/// noticeAware: 0 - 1, how strongly the world feels the viewer: the strength of the flow around them (Flow only; their size stays). Set by NoticeSensor.
/// noticeDt: Seconds since this effect's last update, from the Delta Time (VFX) node. Flow moves each dot's remembered offset by it.
void IdleVeil(inout VFXAttributes attributes, in float alpha, in float size, in float brightness, in float fog,
             in float farAlpha, in float horizon, in float wave, in float refl, in float lineAlpha,
             in float colorSpread, in float colorShift, in float forkGap, in float gatherPull, in float extendLen,
             in float receiverGlow, in float transferAmount, in float transferEvery, in float transferTime, in float depthPeriod,
             in float widthFollow, in float runSeed,
              in float noticeMode, in float noticeClock, in float noticeStay, in float noticeLong, in float noticeViewerX, in float noticeViewerY,
              in float noticeQuiet, in float noticeQuietFrom, in float noticeQuietUntil, in float noticeQuietFrom2, in float noticeQuietUntil2,
              in float noticeWidthStay, in float noticeWidthLong, in float noticeHeightStay,
              in float noticeHeightLong, in float noticeRim, in float noticeRimEven,
              in float noticeRagged, in float noticeWidthWobble, in float noticeTilt,
              in float noticeOrbitStay, in float noticeOrbitLong, in float noticeReachStay,
              in float noticeReachLong, in float noticeInside, in float noticePulseSweep,
              in float noticePulseStop,
              in float noticeWakeX, in float noticeWakeY, in float noticeCoreKeep, in float noticeDeflect,
              in float noticeAware, in float noticeDt)
{
    uint id = attributes.particleId;
    float age = attributes.age;
    attributes.position = attributes.position;
    attributes.color = attributes.color;
    attributes.alpha = attributes.alpha;
    attributes.size = attributes.size;
    Idle_ALPHA = alpha; Idle_SIZE = size; Idle_BRIGHT = brightness; Idle_FOG = fog; Idle_FAR_ALPHA = farAlpha;
    Idle_HORIZON = horizon; Idle_WAVE = wave; Idle_REFL = refl; Idle_LINE_ALPHA = lineAlpha;
    Idle_COLOR_SPREAD = colorSpread; Idle_COLOR_SHIFT = colorShift; Idle_GAP = forkGap; Idle_GATHER = gatherPull;
    Idle_EXTEND = extendLen; Idle_GLOW = receiverGlow;
    Idle_XAMT = transferAmount; Idle_XINT = transferEvery; Idle_XDUR = transferTime; Idle_ZPERIOD = depthPeriod; Idle_WFOLLOW = widthFollow; Idle_RS = (uint)runSeed * 2654435761u;
    attributes.age = attributes.age;
    Idle_NOTICE_MODE = (int)(noticeMode + 0.5);
    if (Idle_NOTICE_MODE > 0) attributes.age = noticeClock;
    Idle_NOTICE.stay = noticeStay; Idle_NOTICE.longStay = noticeLong; Idle_NOTICE.viewerX = noticeViewerX; Idle_NOTICE.viewerY = noticeViewerY; Idle_NOTICE.clock = attributes.age;
    Idle_NOTICE.widthStay = noticeWidthStay;
    Idle_NOTICE.widthLong = noticeWidthLong;
    Idle_NOTICE.heightStay = noticeHeightStay;
    Idle_NOTICE.heightLong = noticeHeightLong;
    Idle_NOTICE.rim = noticeRim;
    Idle_NOTICE.rimEven = noticeRimEven;
    Idle_NOTICE.ragged = noticeRagged;
    Idle_NOTICE.widthWobble = noticeWidthWobble;
    Idle_NOTICE.tilt = noticeTilt;
    Idle_NOTICE.orbitStay = noticeOrbitStay;
    Idle_NOTICE.orbitLong = noticeOrbitLong;
    Idle_NOTICE.reachStay = noticeReachStay;
    Idle_NOTICE.reachLong = noticeReachLong;
    Idle_NOTICE.inside = noticeInside;
    Idle_NOTICE.pulseSweep = noticePulseSweep;
    Idle_NOTICE.pulseStop = noticePulseStop;
    Idle_NOTICE.wakeX = noticeWakeX; Idle_NOTICE.wakeY = noticeWakeY; Idle_NOTICE.coreKeep = noticeCoreKeep; Idle_NOTICE.deflect = noticeDeflect;
    Idle_NOTICE.aware = noticeAware;
    if (Idle_NOTICE_MODE > 0)
    {
        Idle_QUIET = noticeQuiet;
        Idle_QWIN = float4(noticeQuietFrom, noticeQuietUntil, noticeQuietFrom2, noticeQuietUntil2);
    }
    // The stored flow offset. Guarded because Idle_Fly compiles this file too and does not store it (VFX defines VFX_USE_<NAME>_CURRENT
    // for every attribute an effect uses).
    float2 noticeOff = 0.0;
    float2 noticeVel = 0.0;
#if defined(VFX_USE_NOTICEOFFSET_CURRENT) && defined(VFX_USE_NOTICEVELOCITY_CURRENT)
    noticeOff = attributes.noticeOffset;
    noticeVel = attributes.noticeVelocity;
#endif
    Idle_Core(attributes, false, noticeOff, noticeVel, noticeDt);
#if defined(VFX_USE_NOTICEOFFSET_CURRENT) && defined(VFX_USE_NOTICEVELOCITY_CURRENT)
    attributes.noticeOffset = noticeOff;
    attributes.noticeVelocity = noticeVel;
#endif
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
/// noticeMode: Which parts of the reaction to a viewer are on, as a bit mask: 1 clear, 2 pulse, 4 focus, 8 flow (instead of the other three; 16 and 32 are test switches). 0 = none (the plain idle). Set by NoticeSensor.
/// noticeClock: The world's clock in seconds, used instead of the particle age while a mode is on; it runs slow during the hush. Set by NoticeSensor.
/// noticeStay: 0 - 1, how far the world is into the stay stage. Set by NoticeSensor.
/// noticeLong: 0 - 1, how far the world is into the long-stay stage. Set by NoticeSensor.
/// noticeViewerX: Screen x of the viewer, -1 - 1, smoothed so it trails. Set by NoticeSensor.
/// noticeViewerY: Screen y of the viewer, -1 - 1, smoothed the same way. Set by NoticeSensor.
/// noticeQuiet: 0 - 1, how quiet the world is while a viewer is there. Calms the transfer. Set by NoticeSensor.
/// noticeQuietFrom: Start (world clock) of the latest quiet window: events that would start inside it are skipped. Set by NoticeSensor.
/// noticeQuietUntil: End of the latest quiet window (a huge number while it lasts). Set by NoticeSensor.
/// noticeQuietFrom2: Start of the window before that. Set by NoticeSensor.
/// noticeQuietUntil2: End of the window before that. Set by NoticeSensor.
/// noticeWidthStay: Half the width of the space the world clears for a viewer after a stay (3 - 10 s), in screen half-heights. The viewer's box in the Game view is 0.18 wide.
/// noticeWidthLong: Half the width after a long stay (over 10 s).
/// noticeHeightStay: Half the height of the cleared space after a stay. The viewer's box is 0.63 tall.
/// noticeHeightLong: Half the height after a long stay.
/// noticeRim: How soft the pile-up on the rim is. Smaller = a wider, softer, more gradual squeeze that bends the ribbons around the space from further away; bigger = a thin hard edge. Clamped to 0.05 - 0.8; about 0.25 reads best.
/// noticeRimEven: How much of the pile-up's extra brightness is cancelled. 0 = a very bright rim, 1 = no glow at all.
/// noticeRagged: How far the edge of the space is bent out of straight, in screen half-heights. 0 = a plain capsule, bigger = a more ragged, wavy edge.
/// noticeWidthWobble: How much the width changes from the top of the space to the bottom (share of the width). 0 = straight sides.
/// noticeTilt: How far the whole space sways to one side and the other, in radians. 0 = always upright.
/// noticeOrbitStay: Share of the dots near the space that leave their ribbons and circle it, after a stay.
/// noticeOrbitLong: The same after a long stay.
/// noticeReachStay: How far from the edge (screen half-heights) a dot can be and still be drawn into orbit, after a stay.
/// noticeReachLong: The same after a long stay.
/// noticeInside: Share of the orbiting dots that are allowed to dip inside the space now and then. Keep it tiny (0.003) or the inside is not empty.
/// noticePulseSweep: Seconds the bright ring takes to come in toward the viewer. Smaller = faster.
/// noticePulseStop: Where the bright ring stops, in steps outside the rim (1 step = 0.35 screen half-heights). About 1.6 is the outer edge of the dots the viewer has pushed aside; bigger = it stops further away.
/// noticeWakeX: Screen x, -1 - 1, of a slower shadow of the viewer. The stretch from the viewer back to it is the tail the field drags behind a moving viewer. Set by NoticeSensor.
/// noticeWakeY: Screen y of that slower shadow. Set by NoticeSensor.
/// noticeCoreKeep: Share of the dots that do not leave the middle of the core, dimmer and smaller the closer to the middle line they are (the far layers keep 3 times as many). The core is already thin on its own, a ramp that is empty on the middle line and full at the edge; this adds a few dots on top. 0 = just the ramp.
/// noticeDeflect: How far the dots slide along the capsule instead of straight out, as a share of how far they are pushed out. 0 = straight out like a wall; 0.6 = about 30 degrees; above 1 = more sliding than pushing. Clamped to 0 - 1.5.
/// noticeAware: 0 - 1, how strongly the world feels the viewer: the strength of the flow around them (Flow only; their size stays). Set by NoticeSensor.
/// noticeDt: Seconds since this effect's last update, from the Delta Time (VFX) node. Flow moves each dot's remembered offset by it.
void IdleVeilReflect(inout VFXAttributes attributes, in float alpha, in float size, in float brightness, in float fog,
                    in float farAlpha, in float horizon, in float wave, in float refl, in float lineAlpha,
                    in float colorSpread, in float colorShift, in float forkGap, in float gatherPull, in float extendLen,
                    in float receiverGlow, in float transferAmount, in float transferEvery, in float transferTime, in float depthPeriod,
                    in float widthFollow, in float runSeed,
                     in float noticeMode, in float noticeClock, in float noticeStay, in float noticeLong, in float noticeViewerX, in float noticeViewerY,
                     in float noticeQuiet, in float noticeQuietFrom, in float noticeQuietUntil, in float noticeQuietFrom2, in float noticeQuietUntil2,
                     in float noticeWidthStay, in float noticeWidthLong, in float noticeHeightStay,
                     in float noticeHeightLong, in float noticeRim, in float noticeRimEven,
                     in float noticeRagged, in float noticeWidthWobble, in float noticeTilt,
                     in float noticeOrbitStay, in float noticeOrbitLong, in float noticeReachStay,
                     in float noticeReachLong, in float noticeInside, in float noticePulseSweep,
                     in float noticePulseStop,
                     in float noticeWakeX, in float noticeWakeY, in float noticeCoreKeep, in float noticeDeflect,
                     in float noticeAware, in float noticeDt)
{
    uint id = attributes.particleId;
    float age = attributes.age;
    attributes.position = attributes.position;
    attributes.color = attributes.color;
    attributes.alpha = attributes.alpha;
    attributes.size = attributes.size;
    Idle_ALPHA = alpha; Idle_SIZE = size; Idle_BRIGHT = brightness; Idle_FOG = fog; Idle_FAR_ALPHA = farAlpha;
    Idle_HORIZON = horizon; Idle_WAVE = wave; Idle_REFL = refl; Idle_LINE_ALPHA = lineAlpha;
    Idle_COLOR_SPREAD = colorSpread; Idle_COLOR_SHIFT = colorShift; Idle_GAP = forkGap; Idle_GATHER = gatherPull;
    Idle_EXTEND = extendLen; Idle_GLOW = receiverGlow;
    Idle_XAMT = transferAmount; Idle_XINT = transferEvery; Idle_XDUR = transferTime; Idle_ZPERIOD = depthPeriod; Idle_WFOLLOW = widthFollow; Idle_RS = (uint)runSeed * 2654435761u;
    attributes.age = attributes.age;
    Idle_NOTICE_MODE = (int)(noticeMode + 0.5);
    if (Idle_NOTICE_MODE > 0) attributes.age = noticeClock;
    Idle_NOTICE.stay = noticeStay; Idle_NOTICE.longStay = noticeLong; Idle_NOTICE.viewerX = noticeViewerX; Idle_NOTICE.viewerY = noticeViewerY; Idle_NOTICE.clock = attributes.age;
    Idle_NOTICE.widthStay = noticeWidthStay;
    Idle_NOTICE.widthLong = noticeWidthLong;
    Idle_NOTICE.heightStay = noticeHeightStay;
    Idle_NOTICE.heightLong = noticeHeightLong;
    Idle_NOTICE.rim = noticeRim;
    Idle_NOTICE.rimEven = noticeRimEven;
    Idle_NOTICE.ragged = noticeRagged;
    Idle_NOTICE.widthWobble = noticeWidthWobble;
    Idle_NOTICE.tilt = noticeTilt;
    Idle_NOTICE.orbitStay = noticeOrbitStay;
    Idle_NOTICE.orbitLong = noticeOrbitLong;
    Idle_NOTICE.reachStay = noticeReachStay;
    Idle_NOTICE.reachLong = noticeReachLong;
    Idle_NOTICE.inside = noticeInside;
    Idle_NOTICE.pulseSweep = noticePulseSweep;
    Idle_NOTICE.pulseStop = noticePulseStop;
    Idle_NOTICE.wakeX = noticeWakeX; Idle_NOTICE.wakeY = noticeWakeY; Idle_NOTICE.coreKeep = noticeCoreKeep; Idle_NOTICE.deflect = noticeDeflect;
    Idle_NOTICE.aware = noticeAware;
    if (Idle_NOTICE_MODE > 0)
    {
        Idle_QUIET = noticeQuiet;
        Idle_QWIN = float4(noticeQuietFrom, noticeQuietUntil, noticeQuietFrom2, noticeQuietUntil2);
    }
    // The stored flow offset. Guarded because Idle_Fly compiles this file too and does not store it (VFX defines VFX_USE_<NAME>_CURRENT
    // for every attribute an effect uses).
    float2 noticeOff = 0.0;
    float2 noticeVel = 0.0;
#if defined(VFX_USE_NOTICEOFFSET_CURRENT) && defined(VFX_USE_NOTICEVELOCITY_CURRENT)
    noticeOff = attributes.noticeOffset;
    noticeVel = attributes.noticeVelocity;
#endif
    Idle_Core(attributes, true, noticeOff, noticeVel, noticeDt);
#if defined(VFX_USE_NOTICEOFFSET_CURRENT) && defined(VFX_USE_NOTICEVELOCITY_CURRENT)
    attributes.noticeOffset = noticeOff;
    attributes.noticeVelocity = noticeVel;
#endif
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
/// noticeMode: Which parts of the reaction to a viewer are on, as a bit mask. 0 = none (the plain idle). Set by NoticeSensor.
/// noticeClock: The world's clock in seconds, used instead of the particle age while a mode is on. Set by NoticeSensor.
/// noticeQuietFrom: Start (world clock) of the latest quiet window: a fly-by that would start inside it is skipped. Set by NoticeSensor.
/// noticeQuietUntil: End of the latest quiet window (a huge number while it lasts). Set by NoticeSensor.
/// noticeQuietFrom2: Start of the window before that. Set by NoticeSensor.
/// noticeQuietUntil2: End of the window before that. Set by NoticeSensor.
void IdleFly(inout VFXAttributes attributes, in float alpha, in float size, in float brightness, in float fog,
            in float farAlpha, in float horizon, in float wave, in float refl, in float lineAlpha,
            in float colorSpread, in float colorShift, in float forkGap, in float gatherPull, in float extendLen,
            in float receiverGlow, in float transferAmount, in float transferEvery, in float transferTime, in float depthPeriod,
            in float widthFollow, in float runSeed,
            in float noticeMode, in float noticeClock, in float noticeQuietFrom, in float noticeQuietUntil,
            in float noticeQuietFrom2, in float noticeQuietUntil2)
{
    uint id = attributes.particleId;
    float age = attributes.age;
    attributes.position = attributes.position;
    attributes.color = attributes.color;
    attributes.alpha = attributes.alpha;
    attributes.size = attributes.size;
    Idle_ALPHA = alpha; Idle_SIZE = size; Idle_BRIGHT = brightness; Idle_FOG = fog; Idle_FAR_ALPHA = farAlpha;
    Idle_RS = (uint)runSeed * 2654435761u;
    attributes.age = attributes.age;
    if ((int)(noticeMode + 0.5) > 0)
    {
        attributes.age = noticeClock;
        Idle_QWIN = float4(noticeQuietFrom, noticeQuietUntil, noticeQuietFrom2, noticeQuietUntil2);
    }
    Idle_FlyCore(attributes);
}
