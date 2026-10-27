// Runs after the Vortex block: takes the line point where Vortex left it, squeezes it out of bodies so lines pile up
// along the outline, blacks out what is still inside and lights the lines hugging the outline in that person's color.

/// Hidden
float BodyDistance(float2 p, float2 center)
{
    // Distance from p to a person's body, taken as a capsule 6 tall and 2 wide around the clicked center.
    // Same capsule as ColorExchange.cs; change both together.
    // ponytail: matches SilhouetteMask Height 6 and a standing pose; read the mask per person if poses vary.
    float2 d = p - center;
    d.y -= clamp(d.y, -2, 2);
    return max(length(d) - 1, 0);
}

/// mask: Connect the SilhouetteMask property (ID mask from SilhouetteMask).
/// persons: Connect the Persons property.
/// count: Connect the PersonCount property.
/// push: How far points are squeezed out of the body, in world units. Keep it at or below SilhouetteMask's
///       Softness: above that, neighbouring points overtake each other and lines zigzag.
/// speedPush: Extra push at walking speed and above. 0.5 = 1.5 times as far while walking. 0 = speed has no effect.
/// rimGlow: Light in the person's carried color (colorB) on lines near the outline. Written to the custom attribute
///          glow (Vector3), which the Output must add last. 0 = off.
/// seepRadius: How close, in world units, this outline must come to another person's body before their color seeps
///             in: half their color where the bodies touch, none at seepRadius apart. 0 = off.
void Silhouette(inout VFXAttributes attributes, VFXSampler2D mask, StructuredBuffer<Person> persons, int count,
                float push, float speedPush, float rimGlow, float seepRadius)
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
    bool found = soft.y > 0.01 && i >= 0 && i < min(count, 8);
    float speed = found ? length(persons[i].velocity) : 0;
    // 0 standing, 1 at walking pace: crossing the 20-unit view in about 3 seconds is ~7 units / second.
    float walk = saturate(speed / 7);

    // Squeeze outward by push x soft^2: deeper points travel farther, so everything from inside lands just past
    // the outline in the same order it started (no zigzag), packed tightest at the outline and easing back outward.
    p -= grad / max(slope, 1e-4) * push * (1 + speedPush * walk) * soft.y * soft.y;

    // Rim color: the person's carried color, with the side facing someone else seeping into theirs, up to half
    // where that person stands. Far from everyone the glow is ~0 anyway, so white there changes nothing.
    float3 tint = 1;
    if (found)
    {
        float3 sum = persons[i].colorB.rgb;
        float total = 1;
        for (int j = 0; j < min(count, 8); j++)
        {
            if (j == i) continue;
            float w = 1 - smoothstep(0, max(seepRadius, 1e-4), BodyDistance(p, persons[j].position));
            sum += persons[j].colorB.rgb * w;
            total += w;
        }
        tint = sum / total;
    }

    // Still inside the hard body after squeezing = black.
    float inside = SampleTexture(mask, p / float2(20, 10) + 0.5, 0).y;
    // Deep inside with almost no slope = the middle of a limb, where "outward" flips side. Points there split to
    // both sides and the strip would draw a bright segment straight across the limb; darken them instead.
    // ponytail: thresholds tuned for Softness ~1 (outline slope ~0.8); retune if Softness changes a lot.
    float middle = smoothstep(0.5, 0.7, soft.y) * (1 - smoothstep(0.1, 0.3, slope));

    float visible = (1 - inside) * (1 - middle);
    // Assign whole attributes: VFX only treats `attributes.x =` as a write (see Vortex.hlsl).
    attributes.position = float3(p, attributes.position.z);
    // The rim goes into the custom attribute glow, which the Output adds after its Multiply gradients: multiplied,
    // the dark blue gradient would wipe out the person's color.
    attributes.glow = attributes.color * rimGlow * soft.y * tint * visible;
    attributes.color = attributes.color * visible;
}
