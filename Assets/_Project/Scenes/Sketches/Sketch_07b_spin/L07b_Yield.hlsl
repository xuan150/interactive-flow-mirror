// Sketch 07b 生 (look-dev, throwaway). Update block of L07b_Lines.vfx, after Vortex; replaces Silhouette.
// The strands push the background open: lines around a viewer are pushed clear of a gap that widens as the viewer
// stays (and their strands get spun), reaches farther ahead of a walking viewer, and closes in again slowly behind
// them and after they leave. Lines squeezed together are dimmed, so the gap's edge stays dark instead of piling up.
// `Person` comes from FlowMirror.Person ([VFXType]); the buffer is declared before this file is included.

// Capsule around the viewer's center, as in L07b_Spin.hlsl / ColorExchange.cs: half height of the straight part.
#define L07B_Y_H 2.0
// Farthest the real outline reaches from the capsule's axis (shoulders), in world units.
#define L07B_Y_WIDE 1.8
// The squeeze reaches this many gaps out from the outline.
#define L07B_Y_REACH 3.0
// Body gap, in world units, below which a viewer's gap closes on the side facing another viewer. About Spin's forkGap.
#define L07B_Y_SHARE 2.0

/// Hidden
float L07b_YPairGap(float2 a, float2 b)
{
    // Gap between two viewers' body capsules, as PairGap in L07b_Spin.hlsl.
    float2 d = a - b;
    d.y = max(abs(d.y) - 2 * L07B_Y_H, 0);
    return max(length(d) - 2, 0);
}

/// Hidden
float L07b_YInside(VFXSampler2D mask, float2 p, int index)
{
    // 1 inside viewer `index`'s hard body. Mask texel: x = (index + 1) x coverage, y = coverage (bilinear).
    float2 m = SampleTexture(mask, p / float2(20, 10) + 0.5, 0).xy;
    return m.y > 0.5 && abs(m.x / m.y - (index + 1)) < 0.5 ? 1 : 0;
}

/// Hidden
float L07b_YOutline(VFXSampler2D mask, float2 p, float2 ray, float r, int index)
{
    // Signed distance from p to viewer `index`'s outline along `ray`, the ray from the capsule's axis through p
    // (r = how far p is from the axis): positive outside, negative inside. 1e3 = no body on the ray.
    bool inside = L07b_YInside(mask, p, index) > 0;
    // Outside: skip the empty stretch beyond the widest the body gets, then march in. Inside: march out.
    float skip = inside ? 0 : max(r - L07B_Y_WIDE, 0);
    float2 from = p - ray * skip;
    float2 way = inside ? ray : -ray;
    for (int i = 1; i <= 30; i++)
    {
        if (!inside && skip + i * 0.06 > r) break;
        if (L07b_YInside(mask, from + way * (i * 0.06), index) != (inside ? 1 : 0))
        {
            float lo = (i - 1) * 0.06;
            float hi = i * 0.06;
            for (int k = 0; k < 3; k++)
            {
                float mid = 0.5 * (lo + hi);
                if (L07b_YInside(mask, from + way * mid, index) != (inside ? 1 : 0)) hi = mid;
                else lo = mid;
            }
            float d = skip + 0.5 * (lo + hi);
            return inside ? -d : d;
        }
    }
    return inside ? -1.8 : 1e3;
}

/// mask: Connect the SilhouetteMask property.
/// persons: Connect the Persons property.
/// count: Connect the PersonCount property.
/// dt: Delta Time.
/// gap: How far, in world units, lines are pushed clear of a viewer's outline once they have stayed `grow` seconds.
/// grow: Seconds a viewer must stay for the gap to open fully, about as long as spinning all their strands. Opens
///       fastest at first.
/// plow: Extra gap straight ahead of a walking viewer. 1 = twice as wide at walking pace.
/// openTime: Seconds lines take to make way. Short, so they move out ahead of a walking viewer.
/// closeTime: Seconds lines take to close in again behind a viewer and after they leave.
void Yield(inout VFXAttributes attributes, VFXSampler2D mask, StructuredBuffer<Person> persons, int count, float dt,
           float gap, float grow, float plow, float openTime, float closeTime)
{
    int n = min(count, 8);
    float h = min(dt, 1.0 / 30);

    // Seconds each viewer slot (id % 8, as in L07b_Spin.hlsl) has been here, 0 = absent. Every point keeps its own
    // count; they all count the same.
    float4 hereA = 0;
    float4 hereB = 0;
    for (int j = 0; j < n; j++)
    {
        float s = persons[j].id % 8;
        hereA = max(hereA, (float4)(s == float4(0, 1, 2, 3)));
        hereB = max(hereB, (float4)(s == float4(4, 5, 6, 7)));
    }
    float4 stayA = hereA * (attributes.stayA + h);
    float4 stayB = hereB * (attributes.stayB + h);

    // Where the line point should go: out along the ray from the viewer's axis, so that nothing is left within gap
    // of the outline. Points from the outline to 3 gaps out are squeezed into gap to 3 gaps out, in the same order
    // (no zigzag), and dimmed by how squeezed they are; points inside the body go to the gap's edge, unlit.
    float2 base = attributes.position.xy;
    float2 push = 0;
    float shade = 1;
    for (int k = 0; k < n; k++)
    {
        Person q = persons[k];
        float s = q.id % 8;
        float stay = dot(stayA, (float4)(s == float4(0, 1, 2, 3))) + dot(stayB, (float4)(s == float4(4, 5, 6, 7)));
        float2 axis = q.position + float2(0, clamp(base.y - q.position.y, -L07B_Y_H, L07B_Y_H));
        float r = length(base - axis);
        float2 ray = r > 1e-4 ? (base - axis) / r : float2(1, 0);
        float g = gap * sqrt(saturate(stay / max(grow, 0.05))) * (1 + plow * saturate(dot(ray, q.velocity) / 7));
        // Little gap on the side facing another viewer close by, so the space between two viewers keeps its lines
        // and doesn't read as a dark body of its own.
        for (int m = 0; m < n; m++)
        {
            if (m == k) continue;
            float2 other = persons[m].position - q.position + float2(1e-4, 0);
            float nearby = 1 - smoothstep(0, L07B_Y_SHARE, L07b_YPairGap(q.position, persons[m].position));
            g *= 1 - nearby * smoothstep(0.2, 0.8, dot(ray, normalize(other)));
        }
        float reach = L07B_Y_REACH * g;
        if (g < 1e-3 || r > L07B_Y_WIDE + reach) continue;

        float d = L07b_YOutline(mask, base, ray, r, k);
        float to = 0;
        float squeeze = 1;
        if (d > 1e2)
        {
            // Nothing on the ray: between the feet. Hide, don't push.
            if (r < 1) shade = 0;
            continue;
        }
        if (d < 0)
        {
            to = g;
            squeeze = 0;
        }
        else if (d < reach)
        {
            float e = 1 - d / reach;
            to = d + g * e * e;
            squeeze = 1 - 2 * g / reach * e;
        }
        else continue;
        // Add up, not the larger one: neighbouring points switching between two viewers' pushes zigzag the line.
        push += ray * (to - d);
        shade = min(shade, squeeze);
    }

    // Ease there: quick to make way, slow to close in. z = darkness, eased the same way, so squeezed lines fade back
    // in as they spread out again.
    float3 bend = attributes.bend;
    float3 target = float3(push, 1 - shade);
    float moveRate = dot(push, push) > dot(bend.xy, bend.xy) ? 1 / max(openTime, 0.01) : 1 / max(closeTime, 0.01);
    float darkRate = target.z > bend.z ? 1 / max(openTime, 0.01) : 1 / max(closeTime, 0.01);
    bend += (target - bend) * (1 - exp(-h * float3(moveRate, moveRate, darkRate)));

    float2 p = base + bend.xy;
    // Still inside a hard body = black.
    float inside = SampleTexture(mask, p / float2(20, 10) + 0.5, 0).y;

    // Assign whole attributes: VFX only treats `attributes.x =` as a write (see Vortex.hlsl).
    attributes.position = float3(p, attributes.position.z);
    attributes.bend = bend;
    attributes.stayA = stayA;
    attributes.stayB = stayB;
    // No rim light in 07b; the Output adds glow last.
    attributes.glow = 0;
    attributes.color = attributes.color * (1 - inside) * (1 - bend.z);
}
