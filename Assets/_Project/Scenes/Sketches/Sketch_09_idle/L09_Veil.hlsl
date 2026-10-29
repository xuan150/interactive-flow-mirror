// Sketch 09 idle 光紗 (look-dev, throwaway): particles live on twisting ribbons (the "reference domain" of
// docs/refs/new_test/test.md), spread over three depth layers so they fill the frame, with a dark floor that mirrors them.
// Position, color and alpha are a pure function of (particleId, age), so there is no simulation: the shape is the
// envelope of many particles. Where a ribbon turns edge-on to the camera its particles overlap and the Additive blend
// lights the fold; face-on it stays a thin veil.
// age doubles as the clock: every particle lives ~forever and spawns in the first frame, so age = total time.
// Two entry points share one body: L09Veil (the world) and L09VeilReflect (the same particles mirrored in the floor,
// used by a second VisualEffect with a smaller capacity).
// ponytail: knobs are #defines for now (edit and save to hot-reload); move to Inspector once the look settles.

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
// Dot look. Alpha adds up where particles overlap.
#define L09_SIZE 0.035
#define L09_ALPHA 0.45
#define L09_BRIGHT 1.0
// Edges: a few strands wander out to this many extra half-widths, so the outline dissolves into dust.
#define L09_HALO 2.0

// Horizon: a wavy line on the screen, at height L09_HORIZON on average (screen -1..1), rising and falling by L09_WAVE and
// drifting slowly. The camera is at z = L09_CAM_Z looking straight ahead, vertical FOV 35, aspect 2:1. Every particle is
// compared with the line at its own screen position; the ribbons stay above it and under it is the mirror.
// A few particles sit on the line itself and draw it, broken up, so it is never a ruler-straight stroke.
#define L09_CAM_Z (-14.0)
#define L09_TANH 0.3153
#define L09_HORIZON (-0.8)
#define L09_WAVE 0.1
// How soft the "no crossing" rule is (world units): ribbons ease onto the plane instead of cutting off.
#define L09_MARGIN 0.25
// Mirror brightness, how fast it fades with height above the line, and how much it ripples.
#define L09_REFL 0.4
#define L09_REFL_FADE 4.0
#define L09_RIPPLE 0.06
// Share of particles that draw the horizon line, its thickness in screen units, and its brightness.
#define L09_LINE_SHARE 0.07
#define L09_LINE_THICK 0.08
#define L09_LINE_ALPHA 0.25
static const float L09_SLOPE = -L09_HORIZON * L09_TANH;

/// Hidden
float L09_Line(float nx, float time)
{
    // Screen height (-1..1) of the horizon at screen x = nx.
    return L09_HORIZON + L09_WAVE * (0.6 * sin(2.1 * nx + 0.05 * time) + 0.4 * sin(5.3 * nx - 0.08 * time + 1.7));
}

// Depth cues. The camera is at z = -14; f runs 0 (near layer) to 1 (far layer). Far = fainter, bluer (fades into the fog
// color), finer; near = brighter, deeper color, bigger and sparser.
#define L09_DEPTH_Z 18.0
#define L09_FAR_ALPHA 0.55
#define L09_FOG 0.6
#define L09_NEAR_SIZE 1.3
#define L09_FAR_SIZE 0.8
static const float3 L09_FOG_COLOR = float3(0.04, 0.08, 0.25);

// Layers, near to far: depth (z), size scale (same for all, so perspective alone makes far things small), ribbon length.
// Ribbon -> layer, height of its middle line above the floor, and share of the particles.
static const float L09_LZ[3] = { 0.0, 8.0, 18.0 };
static const float L09_LS[3] = { 0.9, 1.0, 1.0 };
static const float L09_LL[3] = { 22.0, 34.0, 52.0 };
static const uint L09_RL[L09_RIBBONS] = { 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 2 };
static const float L09_RY[L09_RIBBONS] = { 1.2, 4.0, 1.0, 3.6, 6.4, 1.0, 3.2, 5.6, 8.4, 11.4, 14.4 };
static const float L09_RW[L09_RIBBONS] = { 4.0, 4.0, 3.0, 3.0, 3.0, 3.3, 3.3, 3.3, 3.3, 3.3, 3.3 };
#define L09_RW_SUM 36.8

// ---- Evolution (stage 2 will rebuild this in the ribbons' own frame; off for now).
#define L09_EVOLVE 0
#define L09_SLOTS 1
#define L09_SLOT_PHASE 21.5
#define L09_START 5.0
#define L09_T_SPLIT 6.0
#define L09_T_DRIFT 6.0
#define L09_T_REUNITE 8.0
#define L09_T_RELEASE 10.0
#define L09_GAP_MIN 8.0
#define L09_GAP_JIT 5.0
#define L09_OPEN 1.4
#define L09_SLIDE 1.5
#define L09_R0 1.5
#define L09_R1 4.5
#define L09_SEAM 0.5
#define L09_MERGE 1.25

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
    // md palette (cold blue -> lilac -> pink-purple -> warm pink -> warm gold), sRGB, converted to linear below.
    const float3 c[5] = {
        float3(0.396, 0.655, 0.922), float3(0.639, 0.545, 0.910), float3(0.851, 0.647, 0.859),
        float3(0.945, 0.722, 0.773), float3(1.000, 0.835, 0.647) };
    x = saturate(x) * 4.0;
    int i = min((int)x, 3);
    return pow(max(lerp(c[i], c[i + 1], x - i), 0.0), 2.2);
}

/// Hidden
float2 L09_Event(float2 p, float t, uint slot)
{
    // Offset of position p (xy) caused by the event running in `slot` at time t. Events repeat every L09_CYCLE seconds
    // (start moved by a random 0..L09_GAP_JIT), each with its own place and seam direction picked from its index.
    const float total = L09_T_SPLIT + L09_T_DRIFT + L09_T_REUNITE + L09_T_RELEASE;
    const float cycle = total + L09_GAP_MIN + L09_GAP_JIT;
    float tt = t - slot * L09_SLOT_PHASE;
    if (tt < 0.0) return 0;
    float k = floor(tt / cycle);
    uint seed = (uint)k * 31u + slot * 1013u + 7u;
    float e = tt - k * cycle - (k < 0.5 ? L09_START : L09_GAP_JIT * L09_Rand(seed, 20));
    if (e <= 0.0 || e >= total) return 0;

    float2 c = float2(lerp(-4.0, 4.0, L09_Rand(seed, 21)), lerp(-1.5, 1.5, L09_Rand(seed, 22)));
    float a = 1.5708 + (L09_Rand(seed, 23) - 0.5) * 1.2 + (L09_Rand(seed, 24) < 0.5 ? 0.0 : 3.14159);
    float2 n = float2(cos(a), sin(a));
    float2 m = float2(-n.y, n.x);

    float open = smoothstep(0.0, L09_T_SPLIT, e);
    float slide = smoothstep(L09_T_SPLIT, L09_T_SPLIT + L09_T_DRIFT, e);
    float back = smoothstep(L09_T_SPLIT + L09_T_DRIFT, L09_T_SPLIT + L09_T_DRIFT + L09_T_REUNITE, e);
    float release = smoothstep(total - L09_T_RELEASE, total, e);

    float2 q = p - c;
    float side = smoothstep(-L09_SEAM, L09_SEAM, dot(q, n));
    float R = lerp(L09_R0, L09_R1, open);
    float w = exp(-dot(q, q) / (R * R));

    float across = lerp(-open, open * (1.0 - back * (1.0 + L09_MERGE)), side) * L09_OPEN;
    float along = lerp(-slide, slide * (1.0 - 2.0 * back), side) * L09_SLIDE;
    return (n * across + m * along) * (w * (1.0 - release));
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

    // Local frame: T along the ribbon, W across it, N through its thickness. W turns around T as u grows (twist).
    float3 c = L09_Center(u, r, t);
    float3 T = normalize(L09_Center(u + 0.01, r, t) - L09_Center(u - 0.01, r, t));
    float3 A = normalize(cross(T, float3(0, 0, 1)));
    float3 B = cross(T, A);
    float phi = L09_TAU * (L09_TWIST * u + 0.2 * r + 0.06 * t);
    float3 W = cos(phi) * A + sin(phi) * B;
    float3 N = cross(T, W);

    float pinch = 0.5 + 0.5 * sin(L09_TAU * (1.1 * u + 0.23 * r - 0.07 * t));
    float h = L09_WIDTH * s * (0.3 + 0.7 * pinch);
    float v = ((floor(L09_Rand(id, 3) * L09_STRANDS) + 0.5 * L09_Rand(id, 4)) / L09_STRANDS) * 2.0 - 1.0;
    float halo = L09_HALO * pow(L09_Rand(id, 9), 6.0);
    v *= 1.0 + halo;

    float3 pos = c + W * (v * h) + N * ((L09_Rand(id, 5) - 0.5) * L09_THICK * s);
#if L09_EVOLVE
    for (uint e = 0; e < L09_SLOTS; e++)
        pos.xy += L09_Event(pos.xy, attributes.age, e);
#endif

    float f = saturate(pos.z / L09_DEPTH_Z);
    float fade = smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.88, u);
    float alpha = L09_ALPHA * fade * (0.6 + 0.4 * L09_Rand(id, 6)) * (1.0 - 0.5 * saturate(halo / L09_HALO))
                * lerp(1.0, L09_FAR_ALPHA, f);
    float3 color = lerp(L09_Palette(0.1 + 0.35 * u + 0.06 * r), L09_FOG_COLOR, L09_FOG * f);

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
void L09Veil(inout VFXAttributes attributes)
{
    uint id = attributes.particleId;
    float age = attributes.age;
    attributes.position = attributes.position;
    attributes.color = attributes.color;
    attributes.alpha = attributes.alpha;
    attributes.size = attributes.size;
    L09_Core(attributes, false);
}

void L09VeilReflect(inout VFXAttributes attributes)
{
    uint id = attributes.particleId;
    float age = attributes.age;
    attributes.position = attributes.position;
    attributes.color = attributes.color;
    attributes.alpha = attributes.alpha;
    attributes.size = attributes.size;
    L09_Core(attributes, true);
}
