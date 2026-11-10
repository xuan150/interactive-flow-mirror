#ifndef NAMELESS_COMMON_INCLUDED
#define NAMELESS_COMMON_INCLUDED

// Shared by NamelessSim.compute and the two Nameless shaders; ported from docs/lookdev/nameless.html (COMMON).

uint HashU(uint x) { x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16; return x; }
float Hash1(uint x) { return float(HashU(x)) / 4294967295.0; }
float3 Hash3(uint x) { return float3(Hash1(x), Hash1(x ^ 0x9E3779B9u), Hash1(x ^ 0x85EBCA6Bu)); }

// GLSL mod (result takes the divisor's sign); HLSL fmod differs for negative x.
float Mod(float x, float y) { return x - y * floor(x / y); }

// Mod289, Permute, TaylorInvSqrt and SNoise are ported from webgl-noise's noise3D.glsl
// (https://github.com/ashima/webgl-noise, https://github.com/stegu/webgl-noise), under the MIT License:
//
// Copyright (C) 2011 by Ashima Arts (Simplex noise)
// Copyright (C) 2011-2016 by Stefan Gustavson (Classic noise and others)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
float3 Mod289(float3 x) { return x - 289.0 * floor(x / 289.0); }
float4 Mod289(float4 x) { return x - 289.0 * floor(x / 289.0); }
float4 Permute(float4 x) { return Mod289((x * 34.0 + 1.0) * x); }
float4 TaylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

// Simplex noise (Ashima / Gustavson), same as the prototype.
float SNoise(float3 v)
{
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);
    float3 i = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);
    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;
    i = Mod289(i);
    float4 p = Permute(Permute(Permute(i.z + float4(0.0, i1.z, i2.z, 1.0)) + i.y + float4(0.0, i1.y, i2.y, 1.0)) + i.x + float4(0.0, i1.x, i2.x, 1.0));
    float n_ = 1.0 / 7.0;
    float3 ns = n_ * D.wyz - D.xzx;
    float4 j = p - 49.0 * floor(p * ns.z * ns.z);
    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);
    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);
    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);
    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, 0.0);
    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    float3 p0 = float3(a0.xy, h.x), p1 = float3(a0.zw, h.y), p2 = float3(a1.xy, h.z), p3 = float3(a1.zw, h.w);
    float4 nm = TaylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= nm.x; p1 *= nm.y; p2 *= nm.z; p3 *= nm.w;
    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

float3 NVec(float3 p) { return float3(SNoise(p), SNoise(p + float3(19.1, 7.3, -11.7)), SNoise(p + float3(-5.9, 23.3, 13.1))); }

float3 Curl(float3 p)
{
    const float e = 0.1;
    float3 x0 = NVec(p - float3(e, 0, 0)), x1 = NVec(p + float3(e, 0, 0));
    float3 y0 = NVec(p - float3(0, e, 0)), y1 = NVec(p + float3(0, e, 0));
    float3 z0 = NVec(p - float3(0, 0, e)), z1 = NVec(p + float3(0, 0, e));
    return float3((y1.z - y0.z) - (z1.y - z0.y), (z1.x - z0.x) - (x1.z - x0.z), (x1.y - x0.y) - (y1.x - y0.x)) / (2.0 * e);
}

float SegD2(float3 p, float3 a, float3 b)
{
    float3 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    float3 d = pa - ba * h;
    return dot(d, d);
}

#endif
