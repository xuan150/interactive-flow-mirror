// Sketch 07c 霧中 (look-dev, throwaway): a faint colored fog under the lines, drawn by a second Output on the line
// particles as soft overlapping dots, one per fog cell of L07c_FogState.hlsl (every other particle: size 0).
// The fog is a faint cool grey everywhere; around a viewer the fog that is already there takes their color, spreading
// out from the body (state kept by FogState), and it brightens where two viewers' fogs have overlapped for a while.
// Bodies stay dark: a cell inside a body is not drawn.

// Same as L07c_FogState.hlsl.
#define L07C_FOG_ROW 1
#define L07C_FOG_COL 3
// Cell spacing: points are 22/599 apart, lines 10/119.
#define L07C_FOG_DX (22.0 / 599 * L07C_FOG_COL)
#define L07C_FOG_DY (10.0 / 119 * L07C_FOG_ROW)
// Dot size. The dot texture (L07c_FogDot.png) is a gaussian with sigma = 1/6 of this, which has to stay at least
// ~0.7 cells or the grid shows. Bigger = softer dark edge around the bodies.
#define L07C_FOG_SIZE 0.5
// Neighbouring dots add up: scale each one so the knobs below read as on-screen brightness. The gaussian covers
// 0.17 of its quad.
#define L07C_FOG_NORM (L07C_FOG_DX * L07C_FOG_DY / (L07C_FOG_SIZE * L07C_FOG_SIZE * 0.17))

/// Hidden
bool L07cFog_IsCell(float2 rest)
{
    // rest comes from lerp(-11, 11, point / 599) and lerp(-5, 5, line / 119).
    uint row = (uint)round((rest.y + 5) / 10 * 119);
    uint col = (uint)round((rest.x + 11) / 22 * 599);
    return row % L07C_FOG_ROW == 0 && col % L07C_FOG_COL == 0;
}

/// Hidden
float3 L07cFog_Vivid(float3 c)
{
    // The palette is pastel and the fog is dim: push saturation so a viewer's color doesn't go muddy.
    float luma = dot(c, float3(0.299, 0.587, 0.114));
    return max(lerp(luma, c, 1.6), 0);
}

/// mask: Connect the SilhouetteMask property.
/// rest: The particle's home position (connect the x / y Lerps); picks the fog cells.
/// time: Total Time.
/// ambient: Brightness of the fog in the thick of a cloud; on average it is about a quarter of this. Background lines
///          are about 0.02.
/// dyeLift: How much brighter the fog gets where a viewer has colored it. 0 = only the color changes.
/// meetGlow: Extra brightness where two viewers' fogs have overlapped for a while. 4 = five times as bright.
void Fog(inout VFXAttributes attributes, VFXSampler2D mask, float2 rest, float time, float ambient, float dyeLift,
         float meetGlow)
{
    attributes.size = 0;
    if (!L07cFog_IsCell(rest)) return;

    // Slowly drifting clouds with dark gaps between them.
    float cloud = smoothstep(-0.3, 0.6, GeneratePerlinNoise(float3(rest, time * 0.05) + 17.3, 0.1, 2, 0.5, 2).x);

    // Where a viewer has dyed it, the cool grey fog takes their color (palette colors peak at 1; two viewers' colors
    // mix) and fills in, so the color reads as a glow around them.
    float4 fog = attributes.fog;
    float peak = max(fog.r, max(fog.g, fog.b));
    float dyed = saturate(peak);
    float3 hue = lerp(float3(0.6, 0.68, 0.85), L07cFog_Vivid(fog.rgb / max(peak, 1e-4)), dyed);
    cloud = lerp(cloud, max(cloud, 0.7), saturate(max(dyed, fog.a)));
    float3 color = hue * cloud * ambient * (1 + dyeLift * dyed) * (1 + meetGlow * fog.a);

    // Mask texel: (hard index + 1, hard coverage, soft index, soft coverage).
    float body = SampleTexture(mask, rest / float2(20, 10) + 0.5, 0).y;
    attributes.position = float3(rest, 0);
    attributes.size = L07C_FOG_SIZE;
    attributes.alpha = 1;
    attributes.color = color * L07C_FOG_NORM * (1 - body);
}
