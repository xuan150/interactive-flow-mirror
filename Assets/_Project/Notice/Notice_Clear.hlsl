// Notice clear: the world makes room for the viewer and gets curious about them. Dots leave a person-sized, upright, lumpy
// rectangle around the viewer and pile up in a bright rim on its edge; many of the dots nearby are drawn off their ribbons and
// circle the rectangle, each at its own speed and distance. The edge wobbles, bulges and tilts, and the center wanders, so the
// shape is never the same twice, and nothing of the viewer's outline is drawn.
// Needs Notice_Common.hlsl, Notice_Pulse.hlsl, Notice_Focus.hlsl and the Idle_* macros included first.
// Everything is a pure function of (particle, IdleNotice): the flow is worked out first, the push and the orbit are laid on top.
// Work happens in screen half-heights (x = pos.x / (depth * TANH), same for y), so the patch looks the same at every depth.

#ifndef NOTICE_CLEAR_INCLUDED
#define NOTICE_CLEAR_INCLUDED

// The size of the rectangle (widthStay / widthLong / heightStay / heightLong), how soft its rim is (rim), how ragged, uneven and
// tilted it is (ragged / widthWobble / tilt), how many dots orbit it (orbitStay / orbitLong, reachStay / reachLong, inside) are
// Inspector inputs of the veil: see IdleNotice in Notice_Common.hlsl and the input list of IdleVeil.
// Corner radius. Bigger = a rounder, more pill-like patch.
#define Notice_Clear_CORNER 0.10
// How much the width and height each swell and shrink with time (share of the size). 0 = fixed size.
#define Notice_Clear_WOBBLE 0.12
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

// Orbiters: dots that leave their ribbons to circle the rectangle.
// Speed along the edge, in screen half-heights per second; each dot takes its own speed in this range and its own direction.
#define Notice_Orbit_SPEED_MIN 0.15
#define Notice_Orbit_SPEED_MAX 0.6
// Distance from the edge at which a dot circles (most hug the edge), and how far it drifts in and out of that.
#define Notice_Orbit_OFFSET_MIN 0.04
#define Notice_Orbit_OFFSET_MAX 0.35
#define Notice_Orbit_WANDER 0.08
// How deep the few orbiters that dip inside the rectangle go (share of the half-width); how many do is the input "inside".
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

    float scale = (pos.z - Idle_CAM_Z) * Idle_TANH;
    float2 C = float2(n.viewerX * 2.0, n.viewerY)
             + Notice_Clear_WANDER * float2(sin(0.21 * t + 1.0), sin(0.17 * t + 2.0));
    float2 p = pos.xy / scale - C;

    // From the screen into the patch's own space: undo the sway, undo the uneven width, then bend the edge. The patch is a
    // plain rounded box there.
    float sn, cs;
    sincos(n.tilt * sin(0.23 * t + 1.3), sn, cs);
    float2 pr = float2(cs * p.x + sn * p.y, -sn * p.x + cs * p.y);
    float wv = Notice_WidthScale(pr.y, B, t, n.widthWobble);
    float2 ps = float2(pr.x / wv, pr.y);
    float2 pw = ps + Notice_Warp(ps, t, n.ragged) * sw;
    float2 ext = float2(A, B);
    float r = min(Notice_Clear_CORNER * (1.0 + 0.4 * sin(0.31 * t + 0.9)), 0.9 * A);
    float s = Notice_BoxSdf(pw, ext, r);                              // < 0: inside the patch

    float depthF = saturate((pos.z - Notice_Clear_DEPTH_NEAR) / Notice_Clear_DEPTH_SPAN);

    // The push, along the way out of the patch. A dot d = s + A from the middle line of the box is moved out by
    // A * (1 - smoothstep(0, L, d)), L = A / RIM: nothing is left inside, dots beyond L stay where they are, and the move never
    // turns back on itself, so nothing tears. The dots in between pile up on the rim.
    float sFinal = s;
    if ((parts & Notice_PARTS_CLEAR) != 0)
    {
        float2 sg = float2(pw.x >= 0.0 ? 1.0 : -1.0, pw.y >= 0.0 ? 1.0 : -1.0);
        float2 q = abs(pw) - (ext - r);
        float2 qo = max(q, 0.0);
        float2 nrm = (qo.x + qo.y > 0.0) ? normalize(qo) * sg : (q.x > q.y ? float2(sg.x, 0.0) : float2(0.0, sg.y));
        float L = A / max(n.rim, 0.05);
        float x = saturate(max(s + A, 0.0) / L);
        float push = A * (1.0 - x * x * (3.0 - 2.0 * x));
        float fp = 1.0 - n.rim * 6.0 * x * (1.0 - x);     // how squeezed the dots are here (small = piled up)
        alpha *= clamp(pow(max(fp, 1e-3), n.rimEven), 0.4, 1.0);
        float2 dr = float2(nrm.x * push * wv, nrm.y * push);          // back out of the patch's space, onto the screen
        pos.xy += float2(cs * dr.x - sn * dr.y, sn * dr.x + cs * dr.y) * scale;
        sFinal = s + push;

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
                pos.xy = lerp(pos.xy, (C + os) * scale, W);
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
