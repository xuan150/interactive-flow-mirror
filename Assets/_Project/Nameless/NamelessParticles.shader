// Draws NamelessSim's particles as soft additive dots, one camera-facing quad each (D3D has no point size), sized in
// pixels like the prototype's gl_PointSize. Ported from docs/lookdev/nameless.html (VS_LIFE, FS_POINT).
Shader "FlowMirror/Nameless Particles"
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

            StructuredBuffer<float4> _Pos, _Vel;
            float4x4 _Rot;
            float3 _Center, _SweepAxis;
            float4 _PalA0, _PalA1, _PalB0, _PalB1, _Pulse;
            float _Base, _Flash, _Dim, _Tension, _M, _Sweep, _Scale, _PulseAmp, _WorldTime, _ShellA, _ShellB;

            static const float2 Corners[6] = { float2(-1, -1), float2(1, -1), float2(1, 1), float2(-1, -1), float2(1, 1), float2(-1, 1) };

            struct Varyings
            {
                float4 pos : SV_POSITION;
                float2 corner : TEXCOORD0;
                float3 col : TEXCOORD1;
            };

            Varyings Vert(uint vid : SV_VertexID)
            {
                uint i = vid / 6;
                float2 corner = Corners[vid % 6];
                float4 P = _Pos[i], V = _Vel[i];
                float role = P.w;
                float3x3 R = (float3x3)_Rot;
                float3 loc = mul(transpose(R), P.xyz - _Center) / _Scale, dl = normalize(loc + 1e-4);
                float mi = _M, front = 0;
                if (_Sweep > -5)
                {
                    float x = _Sweep - (dot(loc, _SweepAxis) * .5 + .5);
                    mi = smoothstep(-.12, .12, x);
                    front = exp(-x * x / .008);
                }
                float sw = lerp(_ShellA, _ShellB, mi);
                float spd = length(V.xyz);
                float band = (dot(dl, _Pulse.xyz) * .5 + .5 - _Pulse.w) * lerp(8, 9, sw);
                float pw = _PulseAmp * exp(-band * band); // not pow(band, 2): undefined for a negative base in HLSL
                // On the shell the sweep lights the skin only. Lighting the inner core and the circling sparks too gave
                // three offset, moving bands that read as the swept patch shaking, not as one sweep of light.
                if (role < .1 || role > .99) pw *= 1 - sw;
                // The shell's quiet details go straight onto the skin, where inertia cannot smooth them away: a fast
                // radial tremble during a feint or lead-in, and the sweep lifting the skin a little as it passes.
                float3 w = P.xyz + mul(R, dl) * (sw * _Scale * (SNoise(dl * 9 + _WorldTime * 11) * .05 * _Tension + pw * .05));
                bool spark = role > .99;
                // V.w: the shell's crests and lobe tips (and a peeling patch) light up and lean toward the highlight colour
                float3 col = lerp(lerp(_PalA0.rgb, _PalB0.rgb, mi), lerp(_PalA1.rgb, _PalB1.rgb, mi), saturate(spd * .35 + (spark ? .7 : 0) + (role < .1 ? .5 : 0) + V.w * .3));
                // the shell's sweep is much stronger: it is the focal point of a quiet shell (~40% over the skin)
                float b = _Base * (1 + spd * .25 + front * 3 + pw * lerp(2.5, 12, sw) + _Flash * 2.2 + _Tension * lerp(.6, .8, sw) + V.w) * (1 - _Dim);
                if (spark) b *= 3;
                if (role < .1) b *= 1.4;

                Varyings o;
                o.pos = TransformWorldToHClip(w);
                float px = _ScreenParams.y * .5 * abs(UNITY_MATRIX_P._m11); // pixels per unit at distance 1
                float sz = (spark ? .02 : .0085) * px / o.pos.w;
                o.pos.xy += corner * clamp(sz, 1, 20) / _ScreenParams.xy * o.pos.w;
                o.corner = corner;
                o.col = col * b * min(1, sz * sz); // a sub-pixel dot gives the light it would have covered
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
