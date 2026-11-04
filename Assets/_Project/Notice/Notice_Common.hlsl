// What the world knows about the viewer while it notices them (docs/notice.md). Included by Idle_Veil.hlsl after the Idle_*
// macros and before Idle_Core, so Idle_CAM_Z, Idle_TANH, Idle_Rand and Idle_Line are all available here.
// Everything here is a pure function of (particle, IdleNotice): no state, nothing remembered between frames. The one exception is
// Flow (Notice_Flow.hlsl), which keeps an offset per dot in two stored attributes.

#ifndef NOTICE_COMMON_INCLUDED
#define NOTICE_COMMON_INCLUDED

struct IdleNotice
{
    float stay;       // 0..1: how far the world is into the "stay" stage (3-10 s). Rises over seconds, falls during the afterglow.
    float longStay;   // 0..1: how far it is into the "long stay" stage (> 10 s). Same behaviour.
    float viewerX;    // -1..1: screen x of the viewer. Already smoothed on the CPU, so it trails on purpose.
    float viewerY;    // -1..1: screen y of the viewer, smoothed the same way.
    float clock;      // Seconds on the world's clock (the same value the particles' age is set to).
    float wakeX;      // -1..1: where the viewer was a moment ago (a slower shadow of viewerX). The tail runs from the viewer back to it.
    float wakeY;
    float aware;      // 0..1: how strongly the world feels the viewer. Rises a moment after they come in, drains once they leave.

    // The shape of the reaction, tuned in the Inspector (the inputs of the veil; the reflection copies them). Units are screen
    // half-heights unless said otherwise; see the input list of IdleVeil for what each one does.
    float widthStay;
    float widthLong;
    float heightStay;
    float heightLong;
    float rim;
    float rimEven;
    float ragged;
    float widthWobble;
    float tilt;
    float orbitStay;
    float orbitLong;
    float reachStay;
    float reachLong;
    float inside;
    float pulseSweep;
    float pulseStop;
    float coreKeep;
    float deflect;
};

// Which parts of the reaction are on (NoticeSensor sets the Notice Mode input to this bit mask).
#define Notice_PARTS_CLEAR 1
#define Notice_PARTS_PULSE 2
#define Notice_PARTS_FOCUS 4
// Flow: the dots bend around the viewer instead of clearing a space (Notice_Flow.hlsl). Runs instead of Clear, Pulse and Focus.
#define Notice_PARTS_FLOW 8
// Test only: turn one of Flow's two pushes off, to judge the other alone (NoticeSensor's Flow Terms).
#define Notice_FLOW_NO_AVOID 16
#define Notice_FLOW_NO_SLIDE 32

#endif
