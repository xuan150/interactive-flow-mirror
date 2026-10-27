// Sketch 07a 撈 (look-dev, throwaway). Replaces the Vortex and Silhouette blocks of MainLines.
// Every line point rides a spring toward a target. Normally the target is its place in the background; a line that
// passes through a viewer has its middle reeled in and wound around that viewer's outline, so the figure is made of
// the field around it, and the lines unwind back into the field when the viewer leaves.
// `Person` comes from FlowMirror.Person ([VFXType]); the buffer is declared before this file is included.

// Body stand-in that parametrises the strands: a capsule 2 wide and 6 tall around the viewer's center, as in
// ColorExchange.cs. Each strand point is then moved onto the real outline from the SilhouetteMask.
// ponytail: fixed standing size (SilhouetteMask Height 6); per-viewer size comes with webcam.
#define L07A_R 1.0
#define L07A_H 2.0
#define L07A_PI 3.14159265
#define L07A_P (2 * L07A_PI * L07A_R + 4 * L07A_H)
// How far apart neighbouring strand points may get, compared with the background spacing (~3.5 px). Higher = a
// shorter stretch of line is reeled in, but bends start to show corners.
#define L07A_STRETCH 1.8
// Rest-line length each tether uses, in world units. Tethers are straight, so they can stretch a lot.
#define L07A_TETHER 0.4
// Lines whose height is within this of a viewer's center pass through the body and get reeled in.
#define L07A_REACH (L07A_H + L07A_R - 0.05)

/// Hidden
float L07a_Hash(float2 p)
{
    return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

/// Hidden
float4 L07a_Capsule(float s)
{
    // Point (xy) and outward normal (zw) on the capsule outline. s = arc length from the top point, positive going
    // down the right side; wraps around.
    s -= L07A_P * floor(s / L07A_P + 0.5);
    float a = abs(s);
    float q = 0.5 * L07A_PI * L07A_R;
    float2 n;
    float2 p;
    if (a < q)
    {
        n = float2(sin(a / L07A_R), cos(a / L07A_R));
        p = n * L07A_R + float2(0, L07A_H);
    }
    else if (a < q + 2 * L07A_H)
    {
        n = float2(1, 0);
        p = float2(L07A_R, L07A_H - (a - q));
    }
    else
    {
        float f = (a - q - 2 * L07A_H) / L07A_R;
        n = float2(cos(f), -sin(f));
        p = n * L07A_R - float2(0, L07A_H);
    }
    float side = s < 0 ? -1 : 1;
    return float4(p.x * side, p.y, n.x * side, n.y);
}

/// Hidden
float L07a_Entry(float dy)
{
    // Arc length from the top point to where the capsule's right side is at height dy (relative to the center).
    float q = 0.5 * L07A_PI * L07A_R;
    if (dy > L07A_H) return L07A_R * acos(saturate((dy - L07A_H) / L07A_R));
    if (dy > -L07A_H) return q + L07A_H - dy;
    return q + 2 * L07A_H + L07A_R * asin(saturate((-L07A_H - dy) / L07A_R));
}

/// Hidden
float L07a_Inside(VFXSampler2D mask, float2 p, int index)
{
    // 1 inside viewer `index`'s hard body. Mask texel: x = (index + 1) x coverage, y = coverage (bilinear).
    float2 m = SampleTexture(mask, p / float2(20, 10) + 0.5, 0).xy;
    return m.y > 0.5 && abs(m.x / m.y - (index + 1)) < 0.5 ? 1 : 0;
}

/// Hidden
float2 L07a_Outline(VFXSampler2D mask, float2 center, float4 capsule, int index)
{
    // March in along the capsule normal from 0.6 outside it until we enter this viewer's body, then bisect: the strand
    // point lands on the real outline. No hit (the gap between the feet) = stay on the capsule.
    float2 from = center + capsule.xy + capsule.zw * 0.6;
    for (int i = 1; i <= 30; i++)
    {
        if (L07a_Inside(mask, from - capsule.zw * (i * 0.06), index) > 0)
        {
            float lo = (i - 1) * 0.06;
            float hi = i * 0.06;
            for (int k = 0; k < 4; k++)
            {
                float mid = 0.5 * (lo + hi);
                if (L07a_Inside(mask, from - capsule.zw * mid, index) > 0) hi = mid;
                else lo = mid;
            }
            return from - capsule.zw * (0.5 * (lo + hi));
        }
    }
    return center + capsule.xy;
}

/// Hidden
float L07a_BodyGap(float2 p, float2 center)
{
    // Distance from p to a viewer's body capsule; same capsule as ColorExchange.cs.
    float2 d = p - center;
    d.y -= clamp(d.y, -L07A_H, L07A_H);
    return max(length(d) - L07A_R, 0);
}

/// Hidden
float L07a_PairGap(float2 a, float2 b)
{
    // Gap between two viewers' body capsules, as BodyGap in ColorExchange.cs.
    float2 d = a - b;
    d.y = max(abs(d.y) - 2 * L07A_H, 0);
    return max(length(d) - 2 * L07A_R, 0);
}

/// Hidden
float3 L07a_Vivid(float3 c)
{
    // The palette is pastel and thin lines thin it further: push saturation so the hidden color reads.
    float luma = dot(c, float3(0.299, 0.587, 0.114));
    return max(lerp(luma, c, 1.8), 0);
}

/// mask: Connect the SilhouetteMask property.
/// persons: Connect the Persons property.
/// count: Connect the PersonCount property.
/// rest: The point's home position (connect the x / y Lerps).
/// wave: Idle undulation offset in y.
/// time: Total Time.
/// dt: Delta Time.
/// settle: Seconds a typical strand takes to wind onto a viewer, and to let go. Strands vary from 0.35x to 1.6x, most
///         on the quick side: the outline reads early, the slow strands keep arriving after.
/// layers: How far strands spread out from the outline while the viewer stands still, in world units.
/// loose: Extra spread at walking pace. 1.5 = 2.5 times as wide while walking.
/// ribbons: Share of strands (0 ~ 1) that only half follow a moving viewer and trail behind; the rest move with the
///          body, so the figure keeps its shape while walking.
/// loops: Share of strands (0 ~ 1) that wind one more full turn; they are reeled in from farther away.
/// strays: Share of strands (0 ~ 1) with loose bits sticking out of the outline.
/// strandGlow: Brightness of a strand on the outline. Background lines are about 0.02.
/// flowGlow: Light running along the strands while the viewer stands still, on top of strandGlow. 0 = off.
/// revealGap: How close, in world units, another viewer's body must come before a figure shows its hidden color.
/// forkShare: Share of strands (0 ~ 1) that branch off onto the outer layer of the nearest other viewer.
/// forkGap: Body gap, in world units, at which strands start to branch over; fully over when the bodies touch.
/// snapSpeed: Viewer speed (world units / second) above which strands that lag behind snap and fade. 7 = walking.
void Scoop(inout VFXAttributes attributes, VFXSampler2D mask, StructuredBuffer<Person> persons, int count,
           float2 rest, float wave, float time, float dt, float settle, float layers, float loose, float ribbons,
           float loops, float strays, float strandGlow, float flowGlow, float revealGap, float forkShare,
           float forkGap, float snapSpeed)
{
    int n = min(count, 8);
    float2 home = float2(rest.x, rest.y + wave);
    float lineId = round((rest.y + 5) / 10 * 119);

    // Owner: the viewer whose body this line passes and whose reeled-in stretch this point is on. Two viewers on the
    // same line split it halfway between them; when that is too short the extra turn goes first, then the strand
    // gets coarser, never cut.
    int owner = -1;
    float W = 1;
    float L = 0;
    float s0 = 0;
    float dir = 1;
    for (int j = 0; j < n; j++)
    {
        float dy = rest.y - persons[j].position.y;
        if (abs(dy) > L07A_REACH) continue;
        float room = 1e4;
        for (int k = 0; k < n; k++)
            if (k != j && abs(rest.y - persons[k].position.y) <= L07A_REACH)
                room = min(room, 0.5 * abs(persons[k].position.x - persons[j].position.x));
        float e = L07a_Entry(dy);
        float wrap = dy >= 0 ? 2 * e : L07A_P - 2 * e;
        float full = wrap + (L07a_Hash(float2(lineId, persons[j].id)) < loops ? L07A_P : 0);
        float need = full / (2 * L07A_STRETCH) + L07A_TETHER;
        if (need > room)
        {
            full = wrap;
            need = wrap / (2 * L07A_STRETCH) + L07A_TETHER;
        }
        float w = max(min(need, room), 0.6);
        if (abs(rest.x - persons[j].position.x) < w)
        {
            owner = j;
            W = w;
            L = full;
            s0 = -e;
            dir = dy >= 0 ? 1 : -1;
        }
    }

    float2 target = home;
    float onStrand = 0;
    float tau = 0;
    float walk = 0;
    float phase = 0;
    float follow = 0;
    float fork = 0;
    float parting = 0;
    if (owner >= 0)
    {
        float2 c = persons[owner].position;
        uint id = persons[owner].id;
        walk = saturate(length(persons[owner].velocity) / 7);
        phase = L07a_Hash(float2(lineId, id + 0.57));
        follow = L07a_Hash(float2(lineId, id + 0.19)) < ribbons ? 0.5 : 1;

        // Across the reeled-in stretch: tether in (from the background), the wound part, tether out.
        float s = (rest.x - c.x) / W * 0.5 + 0.5;
        float a = min(L07A_TETHER / (2 * W), 0.3);
        tau = saturate((s - a) / (1 - 2 * a)) * L;
        float4 cap = L07a_Capsule(s0 + dir * tau);
        float2 edge = L07a_Outline(mask, c, cap, owner);

        float spread = 1 + loose * walk;
        float off = layers * spread * (L07a_Hash(float2(lineId, id + 0.31)) + 0.5 * sin(tau * 2.1 + phase * 6.283 + time * 0.4));
        if (L07a_Hash(float2(lineId, id + 0.83)) < strays)
            off += 0.6 * spread * pow(0.5 + 0.5 * sin(tau * 1.3 + phase * 12.1 + time * 0.5), 3);
        // Extra turns wind outward instead of retracing the first.
        off += 0.12 * tau / L07A_P;
        float2 wound = edge + cap.zw * max(off, 0.02);

        // Encounter: on some strands, the part facing the nearest other viewer leaves this outline and runs along the
        // near side of theirs, on its outermost layer. The capsule point is mirrored, so it lands on the side facing
        // back here and keeps running the same way (down / up) as the part it replaces.
        int partner = -1;
        float close = 0;
        for (int k = 0; k < n; k++)
        {
            if (k == owner) continue;
            float g = 1 - smoothstep(0, max(forkGap, 1e-4), L07a_PairGap(c, persons[k].position));
            if (g > close)
            {
                close = g;
                partner = k;
            }
        }
        if (partner >= 0 && L07a_Hash(float2(lineId, id + 0.45)) < forkShare)
        {
            float2 other = persons[partner].position;
            float2 toward = normalize(other - c + float2(1e-4, 0));
            fork = close * smoothstep(-0.2, 0.6, dot(cap.zw, toward));
            if (fork > 0.001)
            {
                float4 mirrored = L07a_Capsule(-(s0 + dir * tau));
                float2 outer = L07a_Outline(mask, other, mirrored, partner) + mirrored.zw * (1.5 * layers + 0.15);
                wound = lerp(wound, outer, fork);
            }
            // Moving apart: the branch gets dragged away, stretches, and breaks (below).
            parting = fork > 0.001 && dot(persons[partner].velocity - persons[owner].velocity, toward) > 0.5 ? 1 : 0;
        }

        float tether = smoothstep(0, 1, saturate(min(s, 1 - s) / a));
        target = lerp(home, wound, tether);
        onStrand = smoothstep(0.7, 1, tether);
        follow *= tether;
    }

    // Spring toward the target; the update's Euler integration then moves the point by the new velocity.
    float2 p = attributes.position.xy;
    float2 v = attributes.velocity.xy;
    float lag = length(target - p);
    float h = min(dt, 1.0 / 30);
    // Strands already on the figure move with the body (ribbons only half), so walking doesn't smear the outline;
    // the spring only has to settle the shape.
    if (owner >= 0) p += persons[owner].velocity * follow * (1 - smoothstep(0.5, 1.5, lag)) * h;
    float omega = 4.7 / max(settle * lerp(0.35, 1.6, pow(L07a_Hash(float2(lineId, 7.7)), 2)), 0.05);
    // Settled background points follow the idle wave tightly; released strands drift back at their own pace.
    if (owner < 0) omega = lerp(omega, 8, 1 - saturate(lag / 0.3));
    v += (omega * omega * (target - p) - 1.7 * omega * v) * h;

    // Snap: at speed, strands that lag far behind fade out, then grow back over a few seconds. Same for a branch
    // stretched too far by viewers moving apart.
    float speed = owner >= 0 ? length(persons[owner].velocity) : 0;
    float snapped = (speed > snapSpeed * lerp(0.7, 1.4, L07a_Hash(float2(lineId, 9.1))) && lag > 0.4)
                    || (parting > 0 && lag > 0.8) ? 1 : 0;
    float alpha = saturate(attributes.alpha + h * (snapped > 0 ? -3 : 0.3));

    float3 glow = 0;
    if (owner >= 0)
    {
        Person me = persons[owner];
        // Alone: near colorless (silver or pale gold). The hidden color shows on the side facing someone close, and
        // stays while a carried color lasts (ColorExchange).
        float3 neutral = lerp(float3(0.78, 0.86, 1), float3(1, 0.85, 0.6), L07a_Hash(float2(me.id, 3.1)));
        float seep = 0;
        for (int k = 0; k < n; k++)
            if (k != owner)
                seep = max(seep, 1 - smoothstep(0, max(revealGap, 1e-4), L07a_BodyGap(p, persons[k].position)));
        float carried = saturate(length(me.colorB.rgb - me.colorA.rgb) * 2);
        float3 tint = lerp(neutral, L07a_Vivid(me.colorB.rgb), saturate(max(seep + carried, fork)));
        float arrived = 1 - saturate(lag / 1.5);
        float band = pow(0.5 + 0.5 * sin((tau / 1.5 - time * 0.5 + phase) * 6.283), 16);
        glow = tint * strandGlow * onStrand * (0.3 + 0.7 * arrived) * (1 + flowGlow * band * (1 - walk)) * (1 + fork);
    }

    attributes.position = float3(p, 0);
    attributes.velocity = float3(v, 0);
    attributes.alpha = alpha;
    // Added by the Output after its Multiply gradients (see 06).
    attributes.glow = glow;
    // First frame: start in place instead of flying in from the origin.
    if (attributes.age < 0.05)
    {
        attributes.position = float3(target, 0);
        attributes.velocity = float3(0, 0, 0);
    }
}
