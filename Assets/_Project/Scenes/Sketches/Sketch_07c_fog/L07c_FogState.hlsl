// Sketch 07c 霧中 (look-dev, throwaway): the fog under the lines remembers where viewers have been. Runs in Update
// after Scoop. One line particle out of every L07C_FOG_ROW lines x L07C_FOG_COL points is a fog cell at its rest
// position; it keeps (rgb) the color it has taken from nearby viewers and (a) how much two viewers' fogs have
// overlapped there. L07c_Fog.hlsl draws the cells. Separate file because each context only declares the attributes
// it uses.

// Same as L07c_Fog.hlsl.
#define L07C_FOG_ROW 1
#define L07C_FOG_COL 3
// A cell counts toward a viewer while it is within this of their body capsule (covers arms and the halo).
#define L07C_FOG_OWN 2.0
// SilhouetteMask Softness in the 07c scene: how far out of a body the soft coverage reaches (gaussian sigma = half).
#define L07C_SOFTNESS 2.0

/// Hidden
bool L07cFogState_IsCell(float2 rest)
{
    // rest comes from lerp(-11, 11, point / 599) and lerp(-5, 5, line / 119).
    uint row = (uint)round((rest.y + 5) / 10 * 119);
    uint col = (uint)round((rest.x + 11) / 22 * 599);
    return row % L07C_FOG_ROW == 0 && col % L07C_FOG_COL == 0;
}

/// Hidden
float L07cFogState_BodyGap(float2 p, float2 center)
{
    // Distance from p to a viewer's body capsule (2 x 6), as in ColorExchange.cs.
    float2 d = p - center;
    d.y -= clamp(d.y, -2.0, 2.0);
    return max(length(d) - 1, 0);
}

/// Hidden
float L07cFogState_Outside(VFXSampler2D mask, float2 p)
{
    // Rough distance outside the nearest body outline, from the soft mask coverage: across a straight edge the
    // gaussian blur gives coverage = Phi(-d / sigma) (logistic approximation). Inside a body = 0.
    // Mask texel: (hard index + 1, hard coverage, soft index, soft coverage).
    float c = clamp(SampleTexture(mask, p / float2(20, 10) + 0.5, 0).w, 1e-4, 0.5);
    return 0.5 * L07C_SOFTNESS / 1.702 * log((1 - c) / c);
}

/// mask: Connect the SilhouetteMask property.
/// persons: Connect the Persons property.
/// count: Connect the PersonCount property.
/// rest: The particle's home position (connect the x / y Lerps); picks the fog cells.
/// dt: Delta Time.
/// reach: How far beyond a viewer's outline, in world units, the fog takes their color (at most L07C_SOFTNESS).
/// dyeTime: Seconds the color takes to spread out to reach around a viewer standing still; the fog right at the body
///          takes it almost at once.
/// wake: How much faster a moving viewer colors the fog, per world unit / second of speed, so walking leaves a colored
///       wake behind (it fades over fadeTime). 0 = no wake.
/// fadeTime: Seconds the fog takes to lose a color once the viewer has moved on or left.
/// meetTime: Seconds the overlap of two viewers' fogs takes to brighten fully.
void FogState(inout VFXAttributes attributes, VFXSampler2D mask, StructuredBuffer<Person> persons, int count,
              float2 rest, float dt, float reach, float dyeTime, float wake, float fadeTime, float meetTime)
{
    if (!L07cFogState_IsCell(rest)) return;

    int n = min(count, 8);
    // The colored fog hugs the real outline; the capsule only says whose it is.
    float d = L07cFogState_Outside(mask, rest);
    float shape = 1 - smoothstep(0.4 * reach, max(reach, 1e-4), d);
    float3 dye = 0;
    float strongest = 0;
    float total = 0;
    float pace = 0;
    for (int j = 0; j < n; j++)
    {
        float w = shape * (1 - smoothstep(0, L07C_FOG_OWN, L07cFogState_BodyGap(rest, persons[j].position)));
        // The color a viewer carries (ColorExchange), so after an encounter their fog shows what they took along.
        dye += w * persons[j].colorB.rgb;
        strongest = max(strongest, w);
        total += w;
        pace += w * length(persons[j].velocity);
    }
    // What the others add on top of the strongest fog here: for two viewers, the weaker of the two.
    float meet = saturate(total - strongest);

    float4 fog = attributes.fog;
    float h = min(dt, 1.0 / 30);
    // The color spreads out from the outline: right at the body it takes a moment, at reach dyeTime.
    float spread = (0.3 + dyeTime * saturate(d / max(reach, 1e-4))) / (1 + wake * pace / max(total, 1e-4));
    float dyeRate = dot(dye, 1) > dot(fog.rgb, 1) ? spread : fadeTime;
    fog.rgb = lerp(fog.rgb, dye, 1 - exp(-h / max(dyeRate, 0.01)));
    fog.a = lerp(fog.a, meet, 1 - exp(-h / max(meet > fog.a ? meetTime : fadeTime, 0.01)));
    attributes.fog = fog;
}
