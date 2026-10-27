// Sketch 07a 撈 (look-dev, throwaway): sparse, slowly breathing points inside each figure, drawn by a second Output
// on the line particles. Each particle is either one viewer's dot or hidden (size 0). Separate file from
// L07a_Scoop.hlsl because each context only declares the attributes it uses.

/// Hidden
float L07aDots_Hash(float2 p)
{
    return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

/// mask: Connect the SilhouetteMask property.
/// persons: Connect the Persons property.
/// count: Connect the PersonCount property.
/// rest: The particle's home position (connect the x / y Lerps); only used to pick its dot.
/// time: Total Time.
/// density: Share of particles (0 ~ 1) tried as dots; about 2000 x density dots per figure.
/// brightness: Dot brightness at the top of a breath.
/// dotSize: Dot size in world units (0.1 = ~10 px).
void Dots(inout VFXAttributes attributes, VFXSampler2D mask, StructuredBuffer<Person> persons, int count, float2 rest,
          float time, float density, float brightness, float dotSize)
{
    attributes.size = 0;
    int k = min((int)(L07aDots_Hash(rest) * 8), 7);
    if (k >= count || L07aDots_Hash(rest + float2(0.37, 1.91)) > density) return;

    float2 local = float2(L07aDots_Hash(rest + float2(2.3, 0.7)), L07aDots_Hash(rest + float2(5.1, 3.3))) - 0.5;
    float2 p = persons[k].position + local * float2(2.2, 6);
    // Deep inside this viewer's body only, well clear of the outline the strands wrap.
    // Mask texel: (hard index + 1, hard coverage, soft index, soft coverage).
    float4 m = SampleTexture(mask, p / float2(20, 10) + 0.5, 0);
    if (m.y < 0.99 || abs(m.x - (k + 1)) > 0.01 || m.w < 0.7) return;

    uint id = persons[k].id;
    float3 neutral = lerp(float3(0.78, 0.86, 1), float3(1, 0.85, 0.6), L07aDots_Hash(float2(id, 3.1)));
    // Each dot breathes on its own (~5 s), the whole figure more slowly (~7 s).
    float breath = 0.5 + 0.5 * sin(time * 1.3 + L07aDots_Hash(rest + float2(7.7, 4.4)) * 6.283);
    float body = 0.7 + 0.3 * sin(time * 0.9 + id * 1.7);
    attributes.position = float3(p, 0);
    attributes.size = dotSize;
    attributes.alpha = 1;
    attributes.color = neutral * brightness * breath * body;
}
