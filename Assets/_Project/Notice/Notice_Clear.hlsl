// Notice clear: the world makes room for the viewer as a soft field, in three layers that run into one another.
//   Core   an upright capsule around the viewer. The dots are moved out of it along a ramp, not a cut: the dots nearest the middle
//          line move the most and spread over the core, so its density is lowest in the middle and climbs smoothly to 1 at the edge
//          (no step to see, nothing deleted). A few dots stay where they are (the same few every frame), dimmer and smaller
//          toward the middle, so it is thin, never hollow.
//   Shell  the band around the core. The dots that left pile up here a little (about 1.4x at the peak) and slide along the capsule
//          instead of being pushed straight out: away from the middle line on the upstream side, back toward it on the lee side, like
//          a flow splitting around something soft. Far layers push and slide less and keep more dots in the core than near ones.
//   Wake   while the viewer moves, a soft dim band trails along the wake (a slower shadow of the viewer), so the place they just
//          left is thin for a while and fills back in as the shadow catches up. It only changes the dots' weight (alpha and size),
//          not their place, so it is one continuous trail and not a row of holes.
// The edge wobbles, bulges and tilts, and the center wanders, so the shape is never the same twice. Nothing of the viewer's
// outline is drawn. Many dots near the edge can also be drawn off their ribbons to circle it (orbiters, off in the Inspector
// by setting their share to 0).
// Needs Notice_Common.hlsl, Notice_Pulse.hlsl, Notice_Focus.hlsl and the Idle_* macros included first.
// Everything is a pure function of (particle, IdleNotice): the flow is worked out first, the push and the orbit are laid on top.
// Work happens in screen half-heights (x = pos.x / (depth * TANH), same for y), so the patch looks the same at every depth.

#ifndef NOTICE_CLEAR_INCLUDED
#define NOTICE_CLEAR_INCLUDED

// The size of the capsule (widthStay / widthLong / heightStay / heightLong), how soft its rim is (rim), how ragged, uneven and
// tilted it is (ragged / widthWobble / tilt), how many dots stay in the core (coreKeep), how much the flow slides along it
// (deflect), how many dots orbit it (orbitStay / orbitLong, reachStay / reachLong, inside) are Inspector inputs of the veil: see
// IdleNotice in Notice_Common.hlsl and the input list of IdleVeil.
// How much the width and height each swell and shrink with time (share of the size). 0 = fixed size.
#define Notice_Clear_WOBBLE 0.12
// Core. How fast the density climbs from the middle line to the edge: density = (distance / half-width) ^ RAMP. Bigger = a thinner
// core with a steeper edge; 1 is a straight ramp. Changing it moves how much piles up on the rim (bigger = more).
#define Notice_Core_RAMP 2.0
// The far layers keep this many times more dots in the core than the near ones (1 = the same), and take this share of the push.
#define Notice_Core_FAR_KEEP 3.0
#define Notice_Core_FAR_PUSH 0.8
// How much dimmer and smaller the dots left at the very middle are (share, 0 = as the others).
#define Notice_Core_DIM 0.55
#define Notice_Core_SHRINK 0.2
// How much the roundness of the caps breathes (share of the half-width). 0 = always a full capsule.
#define Notice_Core_BREATH 0.1
// Shell. The far layers slide this share as much as the near ones; each dot slides a little more or less than the next (share).
#define Notice_Deflect_FAR 0.5
#define Notice_Deflect_JITTER 0.25
// Height (share of the capsule's half-height) over which the slide turns from up (upper half) to down (lower half).
#define Notice_Deflect_BAND 0.5
// The lee side keeps this share of the upstream side's slide, and this share of its push. Different on the two sides on purpose.
#define Notice_Deflect_LEE 0.5
#define Notice_Deflect_LEE_PUSH 0.85
// Wake. Longest tail (screen half-heights), and the tail lengths over which the band comes in (shorter than MIN = standing still).
#define Notice_Wake_MAX 1.2
#define Notice_Wake_MIN 0.04
#define Notice_Wake_FULL 0.35
// How much dimmer and smaller the dots in the band are at its strongest (share), how much weaker it is at the far end of the tail
// (share), and how many points along the tail the band is measured at.
#define Notice_Wake_DIM 0.6
#define Notice_Wake_SHRINK 0.15
#define Notice_Wake_FADE 0.6
#define Notice_Wake_SAMPLES 3
// How many of the far layers' dots take part in the orbit, as a share of the near layers' (1 = all layers the same). Every layer
// is cleared; this only keeps the far ones from crowding the rim.
#define Notice_Clear_FAR_SHARE 0.3
// The depth range over which the layers go from taking part fully to taking part FAR_SHARE.
#define Notice_Clear_DEPTH_NEAR 4.0
#define Notice_Clear_DEPTH_SPAN 14.0
// How far the center wanders around the viewer, in screen half-heights. 0 = always right on them.
#define Notice_Clear_WANDER 0.1
// Distance outside the rim, in screen half-heights, that counts as one step in q (the unit the pulse and the focus are measured in).
#define Notice_Clear_QUNIT 0.35

// Orbiters: dots that leave their ribbons to circle the capsule.
// Speed along the edge, in screen half-heights per second; each dot takes its own speed in this range and its own direction.
#define Notice_Orbit_SPEED_MIN 0.15
#define Notice_Orbit_SPEED_MAX 0.6
// Distance from the edge at which a dot circles (most hug the edge), and how far it drifts in and out of that.
#define Notice_Orbit_OFFSET_MIN 0.04
#define Notice_Orbit_OFFSET_MAX 0.35
#define Notice_Orbit_WANDER 0.08
// How deep the few orbiters that dip inside the capsule go (share of the half-width); how many do is the input "inside".
#define Notice_Orbit_CROSS_DEPTH 0.5
// Extra alpha of a dot that is orbiting (1 + this). Bigger = the circling dots stand out more.
#define Notice_Orbit_GLOW 0.3
// Length of the edge at the long-stay size, in screen half-heights; the orbiters' pace is measured against it, so it stays smooth
// while the patch grows.
#define Notice_Orbit_PERIMETER 5.0

// A bend that is added to positions before the edge is measured, so the straight sides ripple. amp is how far (screen half-heights).
/// Hidden
float2 Notice_Warp(float2 p, float t, float amp)
{
    return float2(0.6 * sin(2.7 * p.y + 0.41 * t + 0.3) + 0.4 * sin(4.9 * p.y - 0.29 * t + 2.1),
                  0.6 * sin(3.1 * p.x - 0.37 * t + 1.1) + 0.4 * sin(5.7 * p.x + 0.23 * t + 4.0)) * amp;
}

// How much wider (or narrower) than its base width the patch is at height y; the base height b sets the scale of the waves.
/// Hidden
float Notice_WidthScale(float y, float b, float t, float wobble)
{
    float k = y / max(b, 1e-3);
    return clamp(1.0 + wobble * (0.6 * sin(1.9 * k + 0.31 * t) + 0.4 * sin(3.3 * k - 0.23 * t + 1.7)), 0.5, 1.6);
}

// Signed distance to a rounded box with half-extents ext and corner radius r: negative inside, 0 on the edge.
/// Hidden
float Notice_BoxSdf(float2 p, float2 ext, float r)
{
    float2 q = abs(p) - (ext - r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Point at fraction ph (0..1) of the way around the edge of a rounded box, clockwise from the top middle. Moving by equal
// fractions moves equal lengths along the edge, long sides and short sides alike.
/// Hidden
float2 Notice_Perimeter(float ph, float2 ext, float r)
{
    float hx = max(ext.x - r, 0.0);
    float hy = max(ext.y - r, 0.0);
    float arc = 1.5707963 * r;
    float u = ph * (4.0 * hx + 4.0 * hy + 4.0 * arc);
    if (u < hx) return float2(u, ext.y);
    u -= hx;
    if (u < arc) { float a = u / r; return float2(hx + r * sin(a), hy + r * cos(a)); }
    u -= arc;
    if (u < 2.0 * hy) return float2(ext.x, hy - u);
    u -= 2.0 * hy;
    if (u < arc) { float a = u / r; return float2(hx + r * cos(a), -hy - r * sin(a)); }
    u -= arc;
    if (u < 2.0 * hx) return float2(hx - u, -ext.y);
    u -= 2.0 * hx;
    if (u < arc) { float a = u / r; return float2(-hx - r * sin(a), -hy - r * cos(a)); }
    u -= arc;
    if (u < 2.0 * hy) return float2(-ext.x, -hy + u);
    u -= 2.0 * hy;
    if (u < arc) { float a = u / r; return float2(-hx - r * cos(a), hy + r * sin(a)); }
    u -= arc;
    return float2(-hx + u, ext.y);
}

/// Hidden
void Notice_Body(inout float3 pos, inout float3 color, inout float alpha, inout float sizeMul,
                 uint id, uint ribbon, float u, bool dust, IdleNotice n, int parts)
{
    if (parts == 0 || (n.stay <= 0.0 && n.longStay <= 0.0)) return;

    float t = n.clock;
    float sw = smoothstep(0.0, 1.0, n.stay);
    float lw = smoothstep(0.0, 1.0, n.longStay);
    float A = lerp(n.widthStay, n.widthLong, lw) * sw * (1.0 + Notice_Clear_WOBBLE * sin(0.37 * t + 0.6));
    float B = lerp(n.heightStay, n.heightLong, lw) * sw * (1.0 + Notice_Clear_WOBBLE * sin(0.29 * t + 2.4));
    if (A < 1e-3) return;
    B = max(B, 1e-3);                                                // a zero height in the Inspector must not divide by zero below

    float scale = (pos.z - Idle_CAM_Z) * Idle_TANH;
    float2 C0 = float2(n.viewerX * 2.0, n.viewerY)
              + Notice_Clear_WANDER * float2(sin(0.21 * t + 1.0), sin(0.17 * t + 2.0));
    float depthF = saturate((pos.z - Notice_Clear_DEPTH_NEAR) / Notice_Clear_DEPTH_SPAN);

    float sn, cs;
    sincos(n.tilt * sin(0.23 * t + 1.3), sn, cs);
    float2 ext = float2(A, B);
    // Nearly a full round cap, a little less round now and then: the patch is an upright capsule.
    float r = min(A * (1.0 - Notice_Core_BREATH * (0.5 + 0.5 * sin(0.31 * t + 0.9))), 0.9 * B);

    // Core: this dot is one of the few that stay (fixed per dot, so nothing flickers) or not; how much of the push this layer
    // takes; how much it slides.
    bool stayer = Idle_Rand(id, 310) < n.coreKeep * lerp(1.0, Notice_Core_FAR_KEEP, depthF);
    float takes = lerp(1.0, Notice_Core_FAR_PUSH, depthF);
    float slide = clamp(n.deflect, 0.0, 1.5) * lerp(1.0, Notice_Deflect_FAR, depthF)
                * (1.0 + Notice_Deflect_JITTER * (2.0 * Idle_Rand(id, 311) - 1.0));
    float L = A / clamp(n.rim, 0.05, 0.8);                           // how far from the middle line the push reaches
    float D0 = A / (Notice_Core_RAMP + 1.0);                         // the dots this near the middle line end up filling the core

    // Wake: the tail from the viewer back to the slower shadow, and how much of it is long enough to count.
    float2 tail = float2((n.wakeX - n.viewerX) * 2.0, n.wakeY - n.viewerY);
    float tailLen = length(tail);
    tail *= min(1.0, Notice_Wake_MAX / max(tailLen, 1e-4));
    float tailW = smoothstep(Notice_Wake_MIN, Notice_Wake_FULL, min(tailLen, Notice_Wake_MAX));

    // From the screen into the patch's own space: undo the sway, undo the uneven width, then bend the edge. The patch is a plain
    // capsule there.
    float2 p = pos.xy / scale - C0;
    float2 pr = float2(cs * p.x + sn * p.y, -sn * p.x + cs * p.y);
    float wv = Notice_WidthScale(pr.y, B, t, n.widthWobble);
    float2 ps = float2(pr.x / wv, pr.y);
    float2 pw = ps + Notice_Warp(ps, t, n.ragged) * sw;
    float s = Notice_BoxSdf(pw, ext, r);                             // < 0: inside the patch

    // The push, along the way out of the capsule. A dot d from its middle line ends up at dp(d):
    //   d < D0   dp = A * (d / D0) ^ (1 / (RAMP + 1)): the dots nearest the middle line spread over the whole core, so the density
    //            there is (r / A) ^ RAMP: nothing in the middle, a smooth climb to 1 at the edge, no step anywhere;
    //   d >= D0  dp = d + (A - D0) * (1 - smoothstep): the rest are pushed out of the core and the push fades to nothing at L.
    //            The two pieces meet at dp = A with the same slope, and the dots in between pile up a little on the rim.
    // dp rises with d everywhere, so the move never turns back on itself and nothing tears. A dot that stays takes less of the push
    // near the middle line. The push is the outward step plus a sideways step along the capsule, turned by the height: the upper
    // half slides up and the lower half down on the upstream (left) side, and the other way, weaker, on the lee side.
    bool clear = (parts & Notice_PARTS_CLEAR) != 0;
    float pushBody = 0.0;
    if (clear)
    {
        float d = max(s + A, 0.0);
        float dp = d < D0 ? A * pow(d / D0, 1.0 / (Notice_Core_RAMP + 1.0))
                          : d + (A - D0) * (1.0 - smoothstep(0.0, 1.0, (d - D0) / (L - D0)));
        float fs = stayer ? smoothstep(0.0, 1.0, d / A) : 1.0;        // the share of the push this dot takes

        float2 sg = float2(pw.x >= 0.0 ? 1.0 : -1.0, pw.y >= 0.0 ? 1.0 : -1.0);
        float2 q = abs(pw) - (ext - r);
        float2 qo = max(q, 0.0);
        float2 nrm = (qo.x + qo.y > 0.0) ? normalize(qo) * sg : (q.x > q.y ? float2(sg.x, 0.0) : float2(0.0, sg.y));
        float up = smoothstep(0.0, 1.0, 0.5 - nrm.x);                 // 1 on the upstream (left) side, 0 on the lee side
        float shear = -tanh(pw.y / (Notice_Deflect_BAND * B)) * slide * lerp(Notice_Deflect_LEE, 1.0, up);
        float push = (dp - d) * takes * fs * lerp(Notice_Deflect_LEE_PUSH, 1.0, up);
        float2 way = nrm + shear * float2(-nrm.y, nrm.x);              // the outward step plus the step along the edge

        // How squeezed the dots are here (small = piled up): only past D0, where the push is fading out.
        float xs = saturate((d - D0) / (L - D0));
        float fp = 1.0 - takes * (A - D0) / (L - D0) * 6.0 * xs * (1.0 - xs);
        alpha *= clamp(pow(max(fp, 1e-3), n.rimEven), 0.4, 1.0);
        if (stayer)
        {
            alpha *= 1.0 - Notice_Core_DIM * (1.0 - fs);               // dimmer and smaller toward the middle line
            sizeMul *= 1.0 - Notice_Core_SHRINK * (1.0 - fs);
        }
        float2 dr = float2(way.x * wv, way.y) * push;                  // back out of the patch's space, onto the screen
        pos.xy += float2(cs * dr.x - sn * dr.y, sn * dr.x + cs * dr.y) * scale;
        pushBody = push;

        // The wake band: a soft stripe along the tail, as wide as the capsule and fading toward the far end, that makes the dots
        // in it dimmer and smaller. It only starts behind the viewer (never on the shell in front or beside them). A weight, not a
        // push, so the trail is one continuous thin region and not a row of holes.
        if (tailW > 0.0)
        {
            float2 pf = pos.xy / scale - C0;
            float band = 0.0;
            [unroll]
            for (int k = 1; k <= Notice_Wake_SAMPLES; k++)
            {
                float lam = (float)k / (float)Notice_Wake_SAMPLES;
                float sk = Notice_BoxSdf(pf - lam * tail, ext, r);
                band = max(band, (1.0 - smoothstep(0.0, 1.0, (sk + 0.5 * A) / (2.0 * A))) * (1.0 - Notice_Wake_FADE * lam));
            }
            float behind = smoothstep(0.0, 1.0, (dot(pf, tail) / max(length(tail), 1e-4) - 0.2 * A) / (1.2 * A));
            float wk = tailW * band * behind;
            alpha *= 1.0 - Notice_Wake_DIM * wk;
            sizeMul *= 1.0 - Notice_Wake_SHRINK * wk;
        }
    }

    float sFinal = s + pushBody;
    if (clear)
    {
        // Orbiters. Which dots they are is fixed per dot, so nothing flickers; the share only decides how far each has been drawn in.
        float share = lerp(n.orbitStay, n.orbitLong, lw) * sw * lerp(1.0, Notice_Clear_FAR_SHARE, depthF);
        float wh = saturate((share - Idle_Rand(id, 300)) / 0.1);
        if (wh > 0.0)
        {
            float reach = lerp(n.reachStay, n.reachLong, lw);
            float W = wh * (1.0 - smoothstep(0.0, reach, s));
            if (W > 0.0)
            {
                float dir = Idle_Rand(id, 301) < 0.5 ? -1.0 : 1.0;
                float speed = lerp(Notice_Orbit_SPEED_MIN, Notice_Orbit_SPEED_MAX, Idle_Rand(id, 302)) * dir;
                float ph = frac(Idle_Rand(id, 303) + speed * t / Notice_Orbit_PERIMETER);
                float ro = Idle_Rand(id, 304);
                float off = lerp(Notice_Orbit_OFFSET_MIN, Notice_Orbit_OFFSET_MAX, ro * ro * ro);
                off += Notice_Orbit_WANDER * sin(Idle_TAU * (Idle_Rand(id, 306) + t * (0.05 + 0.1 * Idle_Rand(id, 307))));
                // Almost all of them stay outside; the few that are allowed in dip in and out now and then.
                if (Idle_Rand(id, 305) < n.inside)
                    off -= (off + Notice_Orbit_CROSS_DEPTH * A) * (0.5 + 0.5 * sin(Idle_TAU * (Idle_Rand(id, 308) + 0.04 * t)));
                else
                    off = max(off, 0.02);
                off = max(off, -0.9 * A);
                float2 o = Notice_Perimeter(ph, ext + off, max(r + off, 0.02));
                o -= Notice_Warp(o, t, n.ragged) * sw;                           // follow the bent edge
                o.x *= Notice_WidthScale(o.y, B, t, n.widthWobble);                   // and the uneven width and the sway
                float2 os = float2(cs * o.x - sn * o.y, sn * o.x + cs * o.y);
                pos.xy = lerp(pos.xy, (C0 + os) * scale, W);
                alpha *= 1.0 + Notice_Orbit_GLOW * W;
                sFinal = lerp(sFinal, off, W);
            }
        }
    }

    // Where the dot ended up, in steps outside the rim: the pulse and the focus are measured from the rim, whatever its shape.
    float qd = 1.0 + sFinal / Notice_Clear_QUNIT;
    if ((parts & Notice_PARTS_PULSE) != 0) Notice_Pulse(pos, color, alpha, sizeMul, id, qd, scale, saturate(n.stay), t, n.pulseSweep, n.pulseStop);
    if ((parts & Notice_PARTS_FOCUS) != 0) Notice_Focus(color, alpha, sizeMul, qd, n.stay, n.longStay);
}

#endif
