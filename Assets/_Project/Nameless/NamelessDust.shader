// Background dust, seen through its own camera slowly swinging around a pivot: motes in front of and behind the pivot
// slide opposite ways, which reads as deep space. Stateless motes in a wide flat cylinder; out-of-focus
// ones grow and dim. Ported from docs/lookdev/nameless.html (VS_DUST).
//
// The prototype faded a dust buffer by k each frame instead of clearing it, so motes streak. Here each mote is drawn
// once per remembered frame (newest first) with that frame's camera and time, weighted by the fades since: the same
// sum, without a buffer. _TrailFrames must match NamelessWorld.TrailFrames.
//
// URP's ACES crushes the dim end that the prototype's tonemap kept (scene .01 shows as 7/255 here, 20/255 there), and
// most motes are dim, out-of-focus discs. So their floor is doubled (.03 to .06), and NamelessWorld's dustBrightness
// defaults to .28 instead of .22; together they land the dust where the prototype showed it.
Shader "FlowMirror/Nameless Dust"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "Queue" = "Transparent" "RenderType" = "Transparent" }
        Pass
        {
            Blend One One
            ZWrite Off
            ZTest Always
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 4.5
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "NamelessCommon.hlsl"

            #define _TrailFrames 64

            float4x4 _DustView[_TrailFrames]; // the dust camera's view matrix in each remembered frame
            float4 _DustTW[_TrailFrames];     // x: that frame's time, y: how much of its light is left (0 = skip)
            float4 _PalA0;
            float _DustB, _FocusD, _FocalRatio; // _FocalRatio: the dust lens's focal length over this camera's
            float _Motes;                       // how many motes; the draw has _Motes * _TrailFrames quads

            static const float2 Corners[6] = { float2(-1, -1), float2(1, -1), float2(1, 1), float2(-1, -1), float2(1, 1), float2(-1, 1) };

            struct Varyings
            {
                float4 pos : SV_POSITION;
                float2 corner : TEXCOORD0;
                float3 col : TEXCOORD1;
            };

            Varyings Vert(uint vid : SV_VertexID)
            {
                uint motes = (uint)_Motes, q = vid / 6, mote = q % motes, s = q / motes;
                float2 corner = Corners[vid % 6];
                Varyings o;
                o.corner = corner;
                o.col = 0;
                o.pos = float4(0, 0, 0, 1); // all six corners on one point: nothing drawn
                if (_DustTW[s].y < 1e-3) return o;

                float t = _DustTW[s].x;
                // a flat cylinder around the pivot with the camera inside, so the dust is as dense at the frame's edges as
                // behind the body, whatever way the camera faces (a box in front of it piled its far end up in the middle)
                float3 h = Hash3(mote * 11u + 17u);
                float ang = h.x * 6.2831853, rad = 10 * sqrt(h.y);
                float3 p = float3(cos(ang) * rad, h.z * 12 - 6, sin(ang) * rad);
                p += float3(sin(t * .07 + h.y * 20), sin(t * .05 + h.z * 17) * .6, cos(t * .06 + h.x * 13)) * .4;
                p.y = Mod(p.y + t * .03 + 6, 12) - 6;
                // through this camera's projection (so its flip and depth range apply), widened to the dust lens
                float4 cp = mul(UNITY_MATRIX_P, mul(_DustView[s], float4(p, 1)));
                cp.xy *= _FocalRatio;
                float px = _ScreenParams.y * .5 * abs(UNITY_MATRIX_P._m11) * _FocalRatio;
                float base = .011 * px / cp.w;
                float sz = base + abs(cp.w - _FocusD) * .012 * px / cp.w;
                float tw = .5 + .5 * sin(t * (.6 + h.x * 1.7) + h.z * 30);
                // motes right by the camera fade, so no big blot sweeps across the frame
                float b = _DustB * (.35 + .6 * pow(Hash1(mote * 5u + 3u), 12)) * (.4 + .6 * tw) * smoothstep(.5, 1.5, cp.w);
                float ps = clamp(sz, 1, 40);
                o.pos = cp;
                o.pos.xy += corner * ps / _ScreenParams.xy * cp.w;
                o.col = lerp(float3(.75, .8, .85), _PalA0.rgb, .15) * b * clamp(base * base / (ps * ps), .06, 1) * _DustTW[s].y;
                return o;
            }

            half4 Frag(Varyings i) : SV_Target
            {
                float r2 = dot(i.corner, i.corner);
                clip(1 - r2);
                return half4(i.col * exp(-r2 * 2.5), 1);
            }
            ENDHLSL
        }
    }
}
