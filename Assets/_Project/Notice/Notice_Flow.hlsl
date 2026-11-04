// Notice flow: the viewer bends the flow that is already there instead of clearing a space (docs/notice.md, "Flow").
// The idle place of every dot is still worked out from scratch each frame (Idle_Core, untouched). On top of it each dot carries an
// offset and the speed of that offset from one frame to the next (the stored attributes noticeOffset and noticeVelocity). Every
// frame the speed eases toward a target and the offset moves by it:
//   target = aware * strength * h(s) * (AVOID * out + SLIDE * along * edge) - offset / RETURN
//   speed += (target - speed) * (1 - exp(-dt / response));   offset += speed * dt
// out: away from the edge of the viewer's body. edge: along that edge, the way the dot's own flow already runs; a dot whose flow
// hits the edge head-on keeps little of it, plus a hint of up on the upper half and down on the lower half. h(s): strongest on the
// edge, nothing REACH outside it, fading out toward the middle inside it, so the dots that get through keep the middle from
// emptying. The spring is always on: once the viewer leaves and the awareness drains, every dot drifts home.
// Color, alpha and size are not touched. Work happens in screen half-heights, like Clear.
// Needs Notice_Common.hlsl, Notice_Clear.hlsl (the shape helpers) and the Idle_* functions included first.
// docs/notice-flow-check.js is a JS copy of this with numeric checks: keep the two in step.

#ifndef NOTICE_FLOW_INCLUDED
#define NOTICE_FLOW_INCLUDED

// How fast a fully aware dot is moved off the edge and along it, screen half-heights per second.
#define Notice_Flow_AVOID 0.1
#define Notice_Flow_SLIDE 0.3
// How far outside the edge the field reaches (screen half-heights), and the share of the half-width inside the edge over which it
// fades out.
#define Notice_Flow_REACH 0.6
#define Notice_Flow_INNER 0.6
// Along the edge a dot keeps the part of its own flow that runs along the edge; SIGN_BAND is how much counts as all of it. FALLBACK
// is the hint of up on the upper half and down on the lower half, so dots whose flow hits head-on (or the far dust) pick a side.
#define Notice_Flow_SIGN_BAND 0.25
#define Notice_Flow_FALLBACK 0.15
// Spring back home (seconds); never quicker than RETURN_RATIO response times, which keeps the damping ratio at 0.6 or more.
#define Notice_Flow_RETURN 3.0
#define Notice_Flow_RETURN_RATIO 1.5
// Hard limits: offset (screen half-heights), offset speed (half-heights per second), one step (seconds).
#define Notice_Flow_O_MAX 0.8
#define Notice_Flow_W_MAX 0.8
#define Notice_Flow_DT_MAX 0.1
// Each dot wakes up at its own point of the awareness rise (up to this share of it); its strength breathes slowly by this share;
// the far layers take FAR_GAIN of the strength and are FAR_SLOW times slower.
#define Notice_Flow_STAGGER 0.6
#define Notice_Flow_JITTER 0.45
#define Notice_Flow_FAR_GAIN 0.4
#define Notice_Flow_FAR_SLOW 1.5
// Per ribbon (0-1 the far dust, 2-5 the story ribbons): strength, and response time in seconds.
static const float Notice_Flow_GAIN[Idle_RIBBONS] = { 0.35, 0.35, 1.0, 0.7, 0.9, 0.6 };
static const float Notice_Flow_RESP[Idle_RIBBONS] = { 1.4, 1.4, 0.6, 1.0, 0.8, 1.2 };

// The way the dot's idle flow runs on the screen, as a unit vector: along its ribbon's middle line, which it streams along. The far
// dust hardly moves, so it takes the world's flow, left to right.
/// Hidden
float2 Notice_FlowDir(uint ribbon, float u, bool dust, float clock)
{
    if (dust) return float2(1.0, 0.0);
    float tc = clock * Idle_MOTION * Idle_SP[ribbon];
    float zb = Idle_Z0(ribbon, clock);
    float3 a = Idle_Center(u - 0.01, ribbon, tc, zb);
    float3 b = Idle_Center(u + 0.01, ribbon, tc, zb);
    float2 d = b.xy / (b.z - Idle_CAM_Z) - a.xy / (a.z - Idle_CAM_Z);
    return dot(d, d) > 1e-12 ? normalize(d) : float2(1.0, 0.0);
}

// off, vel: the dot's stored offset (screen half-heights) and its speed. dt: seconds since the last update of this effect.
/// Hidden
void Notice_Flow(inout float3 pos, inout float3 color, inout float2 off, inout float2 vel, uint id, uint ribbon, float u, bool dust,
                 IdleNotice n, int parts, float dt)
{
    // A NaN would stay forever in a stored attribute: start that dot over instead.
    if (any(isnan(off)) || any(isnan(vel))) { off = 0.0; vel = 0.0; }
    dt = clamp(dt, 0.0, Notice_Flow_DT_MAX);
    float t = n.clock;
    float scale = (pos.z - Idle_CAM_Z) * Idle_TANH;
    float depthF = saturate((pos.z - Notice_Clear_DEPTH_NEAR) / Notice_Clear_DEPTH_SPAN);

    // This dot: when it wakes up, how strong and how quick it is.
    float stag = Idle_Rand(id, 320) * Notice_Flow_STAGGER;
    float aw = smoothstep(stag, stag + 1.0 - Notice_Flow_STAGGER, n.aware);
    float gain = Notice_Flow_GAIN[ribbon] * lerp(1.0, Notice_Flow_FAR_GAIN, depthF)
               * (1.0 + Notice_Flow_JITTER * sin(Idle_TAU * (Idle_Rand(id, 321) + t * (0.04 + 0.08 * Idle_Rand(id, 322)))));
    float resp = Notice_Flow_RESP[ribbon] * lerp(1.0, Notice_Flow_FAR_SLOW, depthF) * (0.8 + 0.4 * Idle_Rand(id, 323));
    float ret = max(Notice_Flow_RETURN, Notice_Flow_RETURN_RATIO * resp);
    float g = aw * gain;
    if (g <= 0.0 && dot(off, off) + dot(vel, vel) < 1e-12) return;

    float2 goal = -off / ret;
    if (g > 0.0)
    {
        // The body: Clear's capsule at a fixed size. It does not grow with the stay; only the strength does.
        float A = max(n.widthStay * (1.0 + Notice_Clear_WOBBLE * sin(0.37 * t + 0.6)), 1e-3);
        float B = max(n.heightStay * (1.0 + Notice_Clear_WOBBLE * sin(0.29 * t + 2.4)), 1e-3);
        float r = min(A * (1.0 - Notice_Core_BREATH * (0.5 + 0.5 * sin(0.31 * t + 0.9))), 0.9 * B);
        float2 C0 = float2(n.viewerX * 2.0, n.viewerY) + Notice_Clear_WANDER * float2(sin(0.21 * t + 1.0), sin(0.17 * t + 2.0));
        float sn, cs;
        sincos(n.tilt * sin(0.23 * t + 1.3), sn, cs);

        // Where the dot is now (its idle place plus the offset), in the body's own space, as in Clear.
        float2 p = pos.xy / scale + off - C0;
        float2 pr = float2(cs * p.x + sn * p.y, -sn * p.x + cs * p.y);
        float wv = Notice_WidthScale(pr.y, B, t, n.widthWobble);
        float2 ps = float2(pr.x / wv, pr.y);
        float2 pw = ps + Notice_Warp(ps, t, n.ragged);
        float2 ext = float2(A, B);
        float s = Notice_BoxSdf(pw, ext, r);
        float h = s > 0.0 ? 1.0 - smoothstep(0.0, Notice_Flow_REACH, s) : smoothstep(-Notice_Flow_INNER * A, 0.0, s);
        if (h > 0.0)
        {
            float2 sg = float2(pw.x >= 0.0 ? 1.0 : -1.0, pw.y >= 0.0 ? 1.0 : -1.0);
            float2 q = abs(pw) - (ext - r);
            float2 qo = max(q, 0.0);
            float2 nrm = (qo.x + qo.y > 0.0) ? normalize(qo) * sg : (q.x > q.y ? float2(sg.x, 0.0) : float2(0.0, sg.y));
            // A normal goes back through the width scale divided (a move would be multiplied), then the sway is undone.
            float2 d = float2(nrm.x / wv, nrm.y);
            float2 away = float2(cs * d.x - sn * d.y, sn * d.x + cs * d.y);
            away /= length(away) + 1e-6;
            if ((parts & Notice_FLOW_NO_AVOID) == 0) goal += g * Notice_Flow_AVOID * h * away;
            if ((parts & Notice_FLOW_NO_SLIDE) == 0)
            {
                float2 edge = float2(away.y, -away.x);
                float2 flow = Notice_FlowDir(ribbon, u, dust, t) + float2(0.0, Notice_Flow_FALLBACK * tanh(clamp(pw.y / B, -4.0, 4.0)));
                float along = tanh(dot(edge, flow) / Notice_Flow_SIGN_BAND);
                goal += g * Notice_Flow_SLIDE * h * along * edge;
            }
        }
    }

    vel += (goal - vel) * (1.0 - exp(-dt / resp));
    float wl = length(vel);
    if (wl > Notice_Flow_W_MAX) vel *= Notice_Flow_W_MAX / wl;
    off += vel * dt;
    float ol = length(off);
    if (ol > Notice_Flow_O_MAX)
    {
        float2 dir = off / ol;
        off = dir * Notice_Flow_O_MAX;
        vel -= max(dot(vel, dir), 0.0) * dir;                            // no speed left pushing past the limit
    }
    pos.xy += off * scale;
    // Test only: the dots the viewer has moved turn red, the more the further (all of it at 0.2 screen half-heights).
    if ((parts & Notice_FLOW_SHOW_OFFSET) != 0) color = lerp(color, float3(1.0, 0.15, 0.05), saturate(length(off) / 0.2));
}

#endif
