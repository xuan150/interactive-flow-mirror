// Sketch 07b 生 (look-dev, throwaway). Update block of L07b_Strands.vfx, a line system made only of strands.
// Each viewer spins its own strands from the body surface, like a silkworm: a spinneret runs along the outline and
// lays a 3-ply braid, trip after trip, each trip a little farther out. Freshly spun silk floats out first and lies
// down on the outline about a second later. The strands push the background lines open (L07b_Yield.hlsl), and a
// strand that tears off, or is left behind when its viewer leaves, breaks into pieces that lie down along the
// background lines and fade into them. At an encounter some strands bridge over to the other viewer and break one
// by one as they part.
// `Person` comes from FlowMirror.Person ([VFXType]); the buffer is declared before this file is included.

// 120 strips = 8 viewer slots x 5 trips x 3 plies. A viewer's slot is id % 8.
// ponytail: two viewers whose ids are 8 apart would share strands; fine for 3 choreographed viewers.
#define L07B_TRIPS 5
#define L07B_PLIES 3
#define L07B_PER (L07B_TRIPS * L07B_PLIES)
// Body stand-in that parametrises the strands, as in 07a: a capsule 2 wide and 6 tall around the viewer's center,
// as in ColorExchange.cs. Each strand point is then moved onto the real outline from the SilhouetteMask.
// ponytail: fixed standing size (SilhouetteMask Height 6); per-viewer size comes with webcam.
#define L07B_R 1.0
#define L07B_H 2.0
#define L07B_PI 3.14159265
#define L07B_P (2 * L07B_PI * L07B_R + 4 * L07B_H)
// Length along a strand, in world units, over which its 3 plies go once round each other.
#define L07B_BRAID 0.9
// Length of the pieces a dead strand breaks into, each lying down along one background line.
#define L07B_PIECE 1.0

/// Hidden
float L07b_Hash(float2 p)
{
    return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

/// Hidden
float4 L07b_Capsule(float s)
{
    // Point (xy) and outward normal (zw) on the capsule outline. s = arc length from the top point, positive going
    // down the right side; wraps around. The tangent towards larger s is (w, -z).
    s -= L07B_P * floor(s / L07B_P + 0.5);
    float a = abs(s);
    float q = 0.5 * L07B_PI * L07B_R;
    float2 n;
    float2 p;
    if (a < q)
    {
        n = float2(sin(a / L07B_R), cos(a / L07B_R));
        p = n * L07B_R + float2(0, L07B_H);
    }
    else if (a < q + 2 * L07B_H)
    {
        n = float2(1, 0);
        p = float2(L07B_R, L07B_H - (a - q));
    }
    else
    {
        float f = (a - q - 2 * L07B_H) / L07B_R;
        n = float2(cos(f), -sin(f));
        p = n * L07B_R - float2(0, L07B_H);
    }
    float side = s < 0 ? -1 : 1;
    return float4(p.x * side, p.y, n.x * side, n.y);
}

/// Hidden
float L07b_Inside(VFXSampler2D mask, float2 p, int index)
{
    // 1 inside viewer `index`'s hard body. Mask texel: x = (index + 1) x coverage, y = coverage (bilinear).
    float2 m = SampleTexture(mask, p / float2(20, 10) + 0.5, 0).xy;
    return m.y > 0.5 && abs(m.x / m.y - (index + 1)) < 0.5 ? 1 : 0;
}

/// Hidden
float2 L07b_Outline(VFXSampler2D mask, float2 center, float4 capsule, int index)
{
    // March in along the capsule normal from 0.6 outside it until we enter this viewer's body, then bisect: the strand
    // point lands on the real outline. No hit (the gap between the feet) = stay on the capsule.
    float2 from = center + capsule.xy + capsule.zw * 0.6;
    for (int i = 1; i <= 30; i++)
    {
        if (L07b_Inside(mask, from - capsule.zw * (i * 0.06), index) > 0)
        {
            float lo = (i - 1) * 0.06;
            float hi = i * 0.06;
            for (int k = 0; k < 4; k++)
            {
                float mid = 0.5 * (lo + hi);
                if (L07b_Inside(mask, from - capsule.zw * mid, index) > 0) hi = mid;
                else lo = mid;
            }
            return from - capsule.zw * (0.5 * (lo + hi));
        }
    }
    return center + capsule.xy;
}

/// Hidden
float L07b_BodyGap(float2 p, float2 center)
{
    // Distance from p to a viewer's body capsule; same capsule as ColorExchange.cs.
    float2 d = p - center;
    d.y -= clamp(d.y, -L07B_H, L07B_H);
    return max(length(d) - L07B_R, 0);
}

/// Hidden
float L07b_PairGap(float2 a, float2 b)
{
    // Gap between two viewers' body capsules, as BodyGap in ColorExchange.cs.
    float2 d = a - b;
    d.y = max(abs(d.y) - 2 * L07B_H, 0);
    return max(length(d) - 2 * L07B_R, 0);
}

/// Hidden
float3 L07b_Vivid(float3 c)
{
    // The palette is pastel and thin lines thin it further: push saturation so the hidden color reads.
    float luma = dot(c, float3(0.299, 0.587, 0.114));
    return max(lerp(luma, c, 1.8), 0);
}

/// Hidden
float L07b_Wave(float2 p, float time)
{
    // The background lines' idle undulation in y, as the Noise operators feeding Vortex's wave in L07b_Lines.vfx
    // (Perlin, range -0.3 ~ 0.3 at frequency 0.38, gated by a slow one at 0.08). Change both together.
    float3 c = float3(p, time * 1.2);
    float gate = 0.5 + 0.5 * GeneratePerlinNoise(c, 0.08, 1, 0.7, 2).x;
    return 0.3 * GeneratePerlinNoise(c, 0.38, 1, 0.7, 2).x * smoothstep(0.32, 0.56, gate);
}

/// Hidden
float L07b_Row(float2 p, float time)
{
    // Rest y of the background line passing nearest p: lines rest 10/119 apart, then undulate. Neighbouring lines
    // undulate almost together, so the wave at p stands in for the wave at the line's own rest place.
    return clamp(round((p.y - L07b_Wave(p, time) + 5) / 10 * 119), 0, 119) / 119 * 10 - 5;
}

/// mask: Connect the SilhouetteMask property.
/// persons: Connect the Persons property.
/// count: Connect the PersonCount property.
/// rest: The point's place in the line field (connect the x / y Lerps): y picks the strand, x the spot along it.
/// time: Total Time.
/// dt: Delta Time.
/// spinTime: Seconds the spinneret takes to go once round the outline. One trip is 1 to 1.3 rounds.
/// tripGap: Seconds between the start of one trip and the next. All trips are done after about
///          (trips - 1) x tripGap + 1.3 x spinTime.
/// trips: How many trips, or layers of braid, each viewer spins (1 ~ 5), from the outline out. The outer ones
///        are left out, so fewer trips also means a thinner wrap.
/// layers: How far out a fifth trip would lie compared with the first, in world units.
/// braid: How far the 3 plies of a trip swing apart while the viewer stands still, in world units.
/// loose: Extra braid width and spread at walking pace. 1.5 = 2.5 times as wide while walking.
/// drift: How far freshly spun silk floats out before it lies down, in world units. Stray ends float this far too.
/// settle: Seconds a strand takes to catch up with its shape. Ribbons take 3 times as long.
/// ribbons: Share of strands (0 ~ 1) that only half follow a moving viewer and trail behind.
/// strays: Share of strands (0 ~ 1) whose end never lies down. Up to 3 times as many while walking.
/// strandGlow: Brightness of a strand. Background lines are about 0.02.
/// headGlow: Brightness of the spinneret, the tip of a strand being spun (3 plies on top of each other).
/// flowGlow: Light running along finished strands while the viewer stands still, on top of strandGlow. 0 = off.
/// revealGap: How close, in world units, another viewer's body must come before a figure shows its color fully.
/// forkShare: Share of strands (0 ~ 1) that bridge over to another viewer, per viewer.
/// forkGap: Body gap, in world units, at which bridges start to form. Each bridge breaks somewhere between a quarter
///          and 0.7 of this as the viewers part.
/// snapSpeed: Viewer speed (world units / second) above which strands start to tear off; they are spun again once
///            the viewer slows down. 7 = walking.
/// snapFade: Seconds a torn-off strand, or the far half of a broken bridge, takes to lie down into the background
///           lines and fade out.
/// leaveFade: The same for the strands a viewer leaves behind.
/// aloneSat: Saturation of a figure's own color while alone (0 = grey, 1 = the palette color). Near someone, on
///           bridges and while carrying someone's color, it goes vivid.
void Spin(inout VFXAttributes attributes, VFXSampler2D mask, StructuredBuffer<Person> persons, int count, float2 rest,
          float time, float dt, float spinTime, float tripGap, float trips, float layers, float braid, float loose,
          float drift, float settle, float ribbons, float strays, float strandGlow, float headGlow, float flowGlow,
          float revealGap, float forkShare, float forkGap, float snapSpeed, float snapFade, float leaveFade,
          float aloneSat)
{
    int n = min(count, 8);
    float h = min(dt, 1.0 / 30);
    uint strip = (uint)round((rest.y + 5) / 10 * 119);
    uint slot = strip / L07B_PER;
    uint trip = (strip % L07B_PER) / L07B_PLIES;
    uint ply = strip % L07B_PLIES;
    float u = saturate((rest.x + 11) / 22);

    int owner = -1;
    for (int j = 0; j < n; j++)
        if (persons[j].id % 8 == slot) owner = j;
    bool present = owner >= 0;
    uint id = present ? persons[owner].id : 0;
    float2 tk = float2(slot * L07B_TRIPS + trip, id);
    float2 sk = float2(strip, id);

    // Trips start at different places round the body and alternate direction, so they cross.
    float rate = L07B_P / max(spinTime, 0.05);
    float len = L07B_P * (1 + 0.3 * L07b_Hash(tk + 0.1));
    float start = L07B_P * frac(0.382 * trip + L07b_Hash(float2(id, 5.3)));
    float dir = trip % 2 == 0 ? 1 : -1;
    float speed = present ? length(persons[owner].velocity) : 0;
    float snapAt = snapSpeed * lerp(0.7, 2.0, L07b_Hash(sk + 9.1));

    // Encounter: some strands bridge over to another viewer, each strand to the closest it may reach, so a figure
    // can reach several at once. link: how far the bridge has formed (0 ~ 1).
    int partner = -1;
    float close = 0;
    if (present)
        for (int k = 0; k < n; k++)
        {
            if (k == owner || L07b_Hash(float2(strip, persons[k].id) + 0.45) >= forkShare) continue;
            float g = 1 - smoothstep(0, max(forkGap, 1e-4), L07b_PairGap(persons[owner].position, persons[k].position));
            if (g > close)
            {
                close = g;
                partner = k;
            }
        }
    float link = smoothstep(0, 0.3, close);

    // Strand state, the same on every point of a strand. spun: length spun so far, negative while the trip waits
    // its turn, and it keeps counting for a few seconds past the full length so the end lies down too.
    // torn: seconds since the strand died, 0 = attached; positive = torn off, negative = its viewer left.
    // cut.x: seconds since the strand's bridge broke, 0 = whole. cut.y (per point): how far the point was across the
    // bridge then; past halfway it is lost with the far half.
    float wait = -(float)trip * tripGap * rate;
    bool first = attributes.age < 0.05;
    float spun = first ? wait : attributes.spun;
    float torn = first ? 0 : attributes.torn;
    float2 cut = first ? float2(0, 0) : attributes.cut;
    if (torn != 0)
    {
        float life = torn < 0 ? leaveFade : snapFade;
        torn += sign(torn) * h;
        if (abs(torn) >= life)
        {
            // Gone. Spin it again once the viewer slows down; start over for whoever comes next.
            if (!present)
            {
                torn = 0;
                spun = wait;
            }
            else if (speed < snapAt)
            {
                torn = 0;
                spun = 0;
            }
            else torn = sign(torn) * life;
        }
    }
    else if (!present)
    {
        if (spun > 0) torn = -h;
        else spun = wait;
    }
    else
    {
        spun = trip + 0.5 < trips ? min(spun + rate * h, len + 5 * rate) : wait;
        if (spun > 0.5 && speed > snapAt) torn = h;
    }
    // A broken bridge: the far half lies down and fades over snapFade, waits there while the other viewer is still in
    // reach, then the gap in the strand fills back in over a second.
    if (torn != 0) cut.x = 0;
    else if (cut.x > 0)
    {
        float next = cut.x + h;
        if (cut.x <= snapFade && next > snapFade && link > 0) next = snapFade;
        cut.x = next >= snapFade + 1 ? 0 : next;
    }
    bool lost = cut.x > 0 && cut.x <= snapFade && cut.y >= 0.5;

    float2 p = attributes.position.xy;
    float2 v = attributes.velocity.xy;
    float4 home = attributes.home;
    float3 glow = 0;
    if (torn != 0 || lost)
    {
        // Dead: each piece lies down along the background line nearest where it was, undulates with it and stretches
        // along it as it fades, until it is just another background line. Fades to 5 % over its life. The ends of
        // each piece, and the stretch where a bridge broke, go dark (multiplied in every frame; they stay dark), so
        // the strip doesn't draw a join from one piece to the next.
        float life = torn < 0 ? leaveFade : snapFade;
        float age = torn != 0 ? abs(torn) : cut.x;
        float x = home.x + home.z * home.w * (1 + 0.6 * age);
        float2 target = float2(x, home.y + L07b_Wave(float2(x, home.y), time));
        float omega = 4.7 / 0.6;
        v += (omega * omega * (target - p) - 1.7 * omega * v) * h;
        float ends = smoothstep(0.05, 0.15, 0.5 * L07B_PIECE - abs(home.z)) * (lost ? smoothstep(0.5, 0.7, cut.y) : 1);
        glow = attributes.glow * ends * exp(-3 * h / max(life, 0.05));
    }
    else if (!present) v = 0;
    else
    {
        Person me = persons[owner];
        float2 c = me.position;
        float walk = saturate(speed / 7);
        float spread = 1 + loose * walk;

        // Points not spun yet wait inside the spinneret, at the tip.
        float laid = min(spun, len);
        float a = u * len;
        float ae = clamp(a, 0, max(laid, 0));
        float visible = spun > 0 && a <= laid ? 1 : 0;
        float behind = (spun - ae) / rate;
        float s = start + dir * ae;
        float4 cap = L07b_Capsule(s);
        float2 edge = L07b_Outline(mask, c, cap, owner);

        // Both ends sit on the outline: the root comes out of the body, the spinneret runs along it.
        float ends = smoothstep(0, 0.4, ae) * smoothstep(0, 0.15, behind);
        float phase = L07b_Hash(tk + 0.7) * 6.283;
        float plait = braid * spread * (1 + sin(ae * 6.283 / L07B_BRAID + ply * 2.094 + phase));
        float lay = layers * spread * (trip + 0.5 * L07b_Hash(tk + 0.31)) / (L07B_TRIPS - 1);
        // Fresh silk floats out, farthest about 0.4 s after it was spun, and lies down over the next second or so.
        float x = behind / 0.4;
        float floatOut = drift * x * exp(1 - x) * (0.7 + 0.3 * sin(time * 2 + ae * 3 + phase));
        // Strays: the end of some strands never lies down.
        float stray = saturate((strays * (1 + 2 * walk) - L07b_Hash(sk + 0.83)) * 8);
        floatOut += drift * stray * smoothstep(len - 1.5, len, ae) * (0.8 + 0.4 * sin(time * 0.7 + ae * 2.3 + phase));
        // Past one round the trip winds outward instead of retracing itself.
        float2 target = edge + cap.zw * ((plait + lay) * ends + floatOut + 0.12 * ae / L07B_P);

        // Bridge: the part of the strand facing the other viewer leaves this outline, crosses the gap sagging like a
        // hanging thread, grips a short stretch of the other's outer layer (the knot, at a height of its own) and
        // comes back. As they part it stretches until it reaches its own limit and breaks: the half still here
        // springs back, the far half is lost.
        float fork = 0;
        float2 knot = 0;
        if (partner >= 0)
        {
            Person other = persons[partner];
            float2 toward = normalize(other.position - c + float2(1e-4, 0));
            fork = cut.x > 0 ? 0 : link * smoothstep(-0.2, 0.6, dot(cap.zw, toward)) * smoothstep(0, 0.4, ae);
            if (fork > 0.001)
            {
                // Capsule point on the other's facing side, straight part: arc a = quarter circle + (H - height).
                float hk = clamp(lerp(-1.6, 1.6, L07b_Hash(sk + 4.4)) + 0.2 * (edge.y - c.y), -L07B_H, L07B_H);
                float4 kc = L07b_Capsule((toward.x > 0 ? -1 : 1) * (0.5 * L07B_PI * L07B_R + L07B_H - hk));
                knot = L07b_Outline(mask, other.position, kc, partner) + kc.zw * (layers * spread + plait + 0.15);
                float sag = 0.6 * length(knot - target) * fork * (1 - fork);
                target = lerp(target, knot, fork) - float2(0, sag);
            }
            float limit = forkGap * lerp(0.25, 0.7, L07b_Hash(sk + 2.7));
            if (cut.x == 0 && spun > 0.5 && link > 0.5 && dot(other.velocity - me.velocity, toward) > 0.3
                && L07b_PairGap(c, other.position) > limit)
                cut = float2(h, fork);
        }

        float ribbon = L07b_Hash(sk + 0.19) < ribbons ? 1 : 0;
        // The far half of a broken bridge fills back in here: jump there unseen.
        bool back = cut.x > snapFade && attributes.cut.x <= snapFade && cut.y >= 0.5;
        if (visible == 0 || back)
        {
            p = target;
            v = 0;
        }
        else
        {
            // Strands on the figure move with the body (ribbons only half), so walking doesn't smear the outline;
            // the spring only has to settle the shape. Just after a bridge breaks, the half still here springs back
            // with a wobble.
            float lag = length(target - p);
            p += me.velocity * (1 - 0.5 * ribbon) * (1 - smoothstep(0.5, 1.5, lag)) * h;
            float omega = 4.7 / max(settle * (1 + 2 * ribbon), 0.05);
            float damp = cut.x > 0 && cut.x < 1 ? 0.5 : 1.7;
            v += (omega * omega * (target - p) - damp * omega * v) * h;
        }

        // Alone: the figure's own color, low in saturation. It goes vivid on the side facing someone close, on
        // bridges, and while a carried color lasts (ColorExchange).
        float seep = 0;
        for (int m = 0; m < n; m++)
            if (m != owner)
                seep = max(seep, 1 - smoothstep(0, max(revealGap, 1e-4), L07b_BodyGap(p, persons[m].position)));
        float carried = saturate(length(me.colorB.rgb - me.colorA.rgb) * 2);
        float3 soft = max(lerp(dot(me.colorB.rgb, float3(0.299, 0.587, 0.114)), me.colorB.rgb, aloneSat), 0);
        float3 tint = lerp(soft, L07b_Vivid(me.colorB.rgb), saturate(max(seep + carried, fork)));
        float done = spun >= len ? 1 : 0;
        float band = pow(0.5 + 0.5 * sin((ae / 1.5 - time * 0.5 + phase) * 6.283), 16);
        float head = done > 0 ? 0 : exp(-(laid - ae) / 0.12);
        // Where a bridge broke, the stretch around the break stays dark and the lost half fills back in.
        float missing = cut.x > 0 ? smoothstep(0.3, 0.5, cut.y) * (1 - saturate(cut.x - snapFade)) : 0;
        glow = tint * visible * (1 - missing)
               * (strandGlow * (1 + flowGlow * band * done * (1 - walk)) * (1 + fork) + headGlow * head);

        // Where this point lies down if it dies now (see the dead branch above): the background line nearest its
        // piece's middle (x, rest y), its place along the piece, and which way the piece runs in x. Pieces follow
        // this outline; the far half of a bridge lies down as one piece at the knot instead.
        if (fork >= 0.5) home = float4(knot.x, L07b_Row(knot, time), clamp(0.15 * (edge.y - c.y), -0.45, 0.45), 1);
        else
        {
            float piece = (floor(ae / L07B_PIECE) + 0.5) * L07B_PIECE;
            float w = ae - piece;
            float2 mid = p - w * dir * float2(cap.w, -cap.z);
            float runs = dir * L07b_Capsule(start + dir * piece).w >= 0 ? 1 : -1;
            home = float4(mid.x, L07b_Row(mid, time), w, runs);
        }
    }

    // Assign whole attributes: VFX only treats `attributes.x =` as a write.
    attributes.position = float3(p, 0);
    attributes.velocity = float3(v, 0);
    // Added by the Output after its Multiply gradients (black here: strands have no background color).
    attributes.glow = glow;
    attributes.spun = spun;
    attributes.torn = torn;
    attributes.cut = cut;
    attributes.home = home;
}
