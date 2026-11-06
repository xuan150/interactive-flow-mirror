// Notice hybrid: the space comes from Clear, the timing from Flow (docs/notice.md, "Hybrid"). Clear (Notice_Body) works out where
// the dot belongs for the field now, from its idle place, every frame, so the thin region stays put while the ribbons stream
// through it. The dot does not get there at once: it carries a lag (the stored attributes noticeOffset and noticeVelocity, the lag
// and its speed). Every frame the lag first takes the change of the field, Clear's push for the field now minus its push for the
// field last frame at the same idle place, so nothing jumps when the viewer moves, the space grows or is let go; then it eases back
// to 0 with Flow's response time and spring, quick while the field is on (hybridFollow) and slow once it is off (hybridAfterglow).
// A dot that only streams through a still field gets no lag. Final place = idle + push now + lag: one offset, the lag is 0 once
// things settle. Each dot joins the stay ramp at its own point and takes its own slowly breathing share of the push.
// Flow's avoid and slide are not used. Color, alpha and size are Clear's for the field now, by the same share.
// Needs Notice_Common.hlsl, Notice_Clear.hlsl, Notice_Flow.hlsl and the Idle_* functions included first.
// docs/notice-diag/hybrid-check.js is a JS copy of this with the timing checks: keep the two in step.

#ifndef NOTICE_HYBRID_INCLUDED
#define NOTICE_HYBRID_INCLUDED

// The least share of the push a dot takes; each breathes slowly between this and all of it, so the thin region is never complete.
#define Notice_Hybrid_SHARE_MIN 0.75
// Spring time = this * response time: damping ratio about 0.6, a slight overshoot as the dots settle (as Flow).
#define Notice_Hybrid_SPRING 1.5
// Flow's response times per ribbon (Notice_Flow_RESP) are taken as shares of this one (a near story ribbon), so the near ribbons
// answer first and the far dust last.
#define Notice_Hybrid_RESP_REF 0.8

// off, vel: the dot's stored lag (screen half-heights) and its speed. prev: the field last frame. dt: seconds since the last update.
/// Hidden
void Notice_Hybrid(inout float3 pos, inout float3 color, inout float alpha, inout float sizeMul, inout float2 off, inout float2 vel,
                   uint id, uint ribbon, float u, bool dust, IdleNotice n, IdleNotice prev, int parts, float dt)
{
    // A NaN would stay forever in a stored attribute: start that dot over instead.
    if (any(isnan(off)) || any(isnan(vel))) { off = 0.0; vel = 0.0; }
    dt = clamp(dt, 0.0, Notice_Flow_DT_MAX);
    float scale = (pos.z - Idle_CAM_Z) * Idle_TANH;
    float depthF = saturate((pos.z - Notice_Clear_DEPTH_NEAR) / Notice_Clear_DEPTH_SPAN);

    // This dot's share of the push: when it joins the stay ramp, and how much of it it takes just now.
    float stag = Idle_Rand(id, 320) * Notice_Flow_STAGGER;
    float share = lerp(Notice_Hybrid_SHARE_MIN, 1.0, 0.5 + 0.5 * sin(Idle_TAU * (Idle_Rand(id, 321) + n.clock * (0.04 + 0.08 * Idle_Rand(id, 322)))));
    float w = share * smoothstep(stag, stag + 1.0 - Notice_Flow_STAGGER, n.stay);
    float wPrev = share * smoothstep(stag, stag + 1.0 - Notice_Flow_STAGGER, prev.stay);

    // Clear's push for the field now and for the field last frame, both from the idle place and on the same clock, so the edge's
    // own breathing is not lagged.
    float3 idle = pos;
    float3 c = color;
    float a = alpha, sm = sizeMul;
    Notice_Body(pos, c, a, sm, id, ribbon, u, dust, n, parts);
    float3 pp = idle;
    float3 cp = color;
    float ap = alpha, sp = sizeMul;
    prev.clock = n.clock;
    Notice_Body(pp, cp, ap, sp, id, ribbon, u, dust, prev, parts);
    float2 push = (pos.xy - idle.xy) / scale * w;
    float2 pushPrev = (pp.xy - idle.xy) / scale * wPrev;
    color = lerp(color, c, w);
    alpha = lerp(alpha, a, w);
    sizeMul = lerp(sizeMul, sm, w);

    // The field moved: the dot does not, yet. Then the lag eases back to 0.
    off -= push - pushPrev;
    float pace = (n.stay > 0.0 || n.longStay > 0.0) ? n.hybridFollow : n.hybridAfterglow;
    float resp = max(pace, 1e-3) * Notice_Flow_RESP[ribbon] / Notice_Hybrid_RESP_REF * lerp(1.0, Notice_Flow_FAR_SLOW, depthF)
               * (0.8 + 0.4 * Idle_Rand(id, 323));
    float spring = max(Notice_Hybrid_SPRING * resp, dt);                // never more than one step: stable at any dt
    vel += (-off / spring - vel) * (1.0 - exp(-dt / resp));
    off += vel * dt;
    float ol = length(off);
    if (ol > Notice_Flow_O_MAX) off *= Notice_Flow_O_MAX / ol;
    pos.xy = idle.xy + (push + off) * scale;
}

#endif
