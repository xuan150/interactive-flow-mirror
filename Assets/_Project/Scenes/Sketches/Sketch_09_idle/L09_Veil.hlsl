// Sketch 09 idle 光紗 (look-dev, throwaway): particles live on a few twisting ribbons (the "reference domain" of
// docs/refs/new_test/test.md). Position, color and alpha are a pure function of (particleId, age), so there is no
// simulation: the shape is the envelope of many particles. Where a ribbon turns edge-on to the camera its particles
// overlap and the Additive blend lights the fold; face-on it stays a thin veil.
// age doubles as the clock: every particle lives ~forever and spawns within the first second, so age ≈ total time.
// ponytail: knobs are #defines for now (edit and save to hot-reload); move to Inspector once the look settles.

#define L09_TAU 6.2831853
// Ribbons in the cluster, and thin strands per ribbon (the fine striations in the reference).
#define L09_RIBBONS 3
#define L09_STRANDS 24
// World units. Screen is 20 x 10.
#define L09_LENGTH 15.0
#define L09_WIDTH 2.4
#define L09_THICK 0.06
// Full turns of twist along the ribbon.
#define L09_TWIST 1.6
// Structure speed (turns per second of the slow wobble) and flow speed (fraction of the ribbon length per second).
#define L09_MOTION 0.5
#define L09_FLOW 0.015
// Dot look. Alpha adds up where particles overlap.
#define L09_SIZE 0.035
#define L09_ALPHA 0.3
#define L09_BRIGHT 1.0

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
float3 L09_Center(float u, float r, float t)
{
    // Centerline of ribbon r: a long irregular arc from left to right, each ribbon with its own phase.
    float x = (u - 0.5) * L09_LENGTH;
    float y = 1.5 * sin(L09_TAU * (0.55 * u + 0.17 * r + 0.05 * t))
            + 0.6 * sin(L09_TAU * (1.3 * u - 0.11 * t + 0.37 * r))
            + (r - 0.5 * (L09_RIBBONS - 1)) * 0.6;
    float z = 0.9 * sin(L09_TAU * (0.8 * u + 0.3 * r + 0.04 * t));
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

void L09Veil(inout VFXAttributes attributes)
{
    uint id = attributes.particleId;
    float t = attributes.age * L09_MOTION;

    float r = floor(L09_Rand(id, 0) * L09_RIBBONS);
    float u0 = L09_Rand(id, 1);
    float u = frac(u0 + attributes.age * L09_FLOW * (0.5 + L09_Rand(id, 2)));

    // Local frame: T along the ribbon, W across it, N through its thickness. W turns around T as u grows (twist).
    float3 c = L09_Center(u, r, t);
    float3 T = normalize(L09_Center(u + 0.01, r, t) - L09_Center(u - 0.01, r, t));
    float3 A = normalize(cross(T, float3(0, 0, 1)));
    float3 B = cross(T, A);
    float phi = L09_TAU * (L09_TWIST * u + 0.2 * r + 0.06 * t);
    float3 W = cos(phi) * A + sin(phi) * B;
    float3 N = cross(T, W);

    float pinch = 0.5 + 0.5 * sin(L09_TAU * (1.1 * u + 0.23 * r - 0.07 * t));
    float h = L09_WIDTH * (0.3 + 0.7 * pinch);
    float v = ((floor(L09_Rand(id, 3) * L09_STRANDS) + 0.5 * L09_Rand(id, 4)) / L09_STRANDS) * 2.0 - 1.0;

    attributes.position = c + W * (v * h) + N * ((L09_Rand(id, 5) - 0.5) * L09_THICK);

    float fade = smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.88, u);
    attributes.color = L09_Palette(0.15 + 0.5 * u + 0.12 * r) * L09_BRIGHT;
    attributes.alpha = L09_ALPHA * fade * (0.6 + 0.4 * L09_Rand(id, 6));
    attributes.size = L09_SIZE * (0.7 + 0.6 * L09_Rand(id, 7));
}
