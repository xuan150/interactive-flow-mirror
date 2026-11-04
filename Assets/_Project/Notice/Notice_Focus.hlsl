// Notice focus: the world puts its attention on the space around the viewer. Dots at the rim of that space turn crisp (small,
// a little brighter and whiter); dots far from it swell and dim into a soft out-of-focus haze. It only strengthens the other
// parts, so the viewer is never drawn. Needs Notice_Common.hlsl first.
// q is a dot's distance from the rim in steps of Notice_Clear_QUNIT (1 = on the rim, bigger = further out), worked out by
// Notice_Body in Notice_Clear.hlsl.

#ifndef NOTICE_FOCUS_INCLUDED
#define NOTICE_FOCUS_INCLUDED

// Where the crisp zone is centered, in steps outside the rim. Around the rim and the dots that circle it.
#define Notice_Focus_AT 1.6
// Distance from that center (steps) at which the picture is neither sharper nor softer than idle. Bigger = a wider crisp zone.
#define Notice_Focus_WIDTH 1.6
// Dot size multiple in the crisp zone. Smaller = finer, crisper points.
#define Notice_Focus_SHARP_SIZE 0.55
// Dot size multiple far away. Bigger = a softer, blurrier surround.
#define Notice_Focus_BLUR_SIZE 1.9
// Extra alpha in the crisp zone (1 + this). Bigger = brighter; too high burns out where ribbons overlap.
#define Notice_Focus_SHARP_GAIN 0.6
// How strongly alpha drops as dots swell. 2 = the same light per screen area (no overall dimming); lower = a brighter haze.
#define Notice_Focus_BLUR_DIM 1.7
// Pull toward a warm white in the crisp zone.
#define Notice_Focus_TINT 0.2
// Extra contrast at long stay: both the sharpening and the blurring grow by (1 + this).
#define Notice_Focus_LONG_BOOST 0.5

/// Hidden
void Notice_Focus(inout float3 color, inout float alpha, inout float sizeMul, float q, float stay, float longStay)
{
    float k = saturate(max(stay, longStay)) * (1.0 + Notice_Focus_LONG_BOOST * saturate(longStay));
    float dx = (q - Notice_Focus_AT) / Notice_Focus_WIDTH;
    float f = exp2(-dx * dx);                     // 1 in the crisp zone, 0.5 at its edge, 0 far away
    float c = 2.0 * f - 1.0;                      // +1 sharpest .. -1 softest, 0 where idle is untouched
    float sh = max(c, 0.0) * k;
    float bl = max(-c, 0.0) * k;

    float grow = 1.0 + (Notice_Focus_BLUR_SIZE - 1.0) * bl;
    float shrink = 1.0 + (Notice_Focus_SHARP_SIZE - 1.0) * sh;
    sizeMul *= grow * shrink;
    alpha *= (1.0 + Notice_Focus_SHARP_GAIN * sh) * pow(grow, -Notice_Focus_BLUR_DIM);
    color *= 1.0 + 0.5 * Notice_Focus_SHARP_GAIN * sh;
    color = lerp(color, float3(1.0, 0.95, 0.85), saturate(Notice_Focus_TINT * sh));
}

#endif
