// Runs after the Vortex block: takes the line point where Vortex left it, squeezes it out of bodies so lines pile up
// along the outline, blacks out what is still inside and brightens the lines hugging the outline.

/// mask: Connect the SilhouetteMask property (ID mask from SilhouetteMask).
/// persons: Connect the Persons property.
/// count: Connect the PersonCount property.
/// push: How far points are squeezed out of the body, in world units. Keep it at or below SilhouetteMask's
///       Softness: above that, neighbouring points overtake each other and lines zigzag.
/// speedPush: Extra push at walking speed and above. 0.5 = 1.5 times as far while walking. 0 = speed has no effect.
/// rimGlow: Extra brightness on lines near the outline. 0 = off.
void Silhouette(inout VFXAttributes attributes, VFXSampler2D mask, StructuredBuffer<Person> persons, int count,
                float push, float speedPush, float rimGlow)
{
    // The mask covers the camera view, 20 x 10 centered on the origin (PersonTracker.Area).
    // Level 0 because Update runs as a compute shader, which can't pick a mip on its own.
    float2 p = attributes.position.xy;
    float2 uv = p / float2(20, 10) + 0.5;

    // zw = soft body (SilhouetteMask.softness): z = average (index + 1), w = how much body is around,
    // ~0.5 on the outline, rising inside, falling outside.
    float2 soft = SampleTexture(mask, uv, 0).zw;
    // Slope of the soft body per world unit, measured 0.1 units to each side. Points into the body.
    float2 dx = float2(0.1 / 20, 0);
    float2 dy = float2(0, 0.1 / 10);
    float2 grad = float2(SampleTexture(mask, uv + dx, 0).w - SampleTexture(mask, uv - dx, 0).w,
                         SampleTexture(mask, uv + dy, 0).w - SampleTexture(mask, uv - dy, 0).w) / 0.2;
    float slope = length(grad);

    // Which person is nearby: average index / coverage. Blends where two bodies overlap; fine for speed.
    int i = (int)round(soft.x / max(soft.y, 1e-4)) - 1;
    float speed = soft.y > 0.01 && i >= 0 && i < min(count, 8) ? length(persons[i].velocity) : 0;
    // 0 standing, 1 at walking pace: crossing the 20-unit view in about 3 seconds is ~7 units / second.
    float walk = saturate(speed / 7);

    // Squeeze outward by push x soft^2: deeper points travel farther, so everything from inside lands just past
    // the outline in the same order it started (no zigzag), packed tightest at the outline and easing back outward.
    p -= grad / max(slope, 1e-4) * push * (1 + speedPush * walk) * soft.y * soft.y;

    // Still inside the hard body after squeezing = black.
    float inside = SampleTexture(mask, p / float2(20, 10) + 0.5, 0).y;
    // Deep inside with almost no slope = the middle of a limb, where "outward" flips side. Points there split to
    // both sides and the strip would draw a bright segment straight across the limb; darken them instead.
    // ponytail: thresholds tuned for Softness ~1 (outline slope ~0.8); retune if Softness changes a lot.
    float middle = smoothstep(0.5, 0.7, soft.y) * (1 - smoothstep(0.1, 0.3, slope));

    // Assign whole attributes: VFX only treats `attributes.x =` as a write (see Vortex.hlsl).
    attributes.position = float3(p, attributes.position.z);
    attributes.color = attributes.color * (1 + rimGlow * soft.y) * (1 - inside) * (1 - middle);
}
