using UnityEngine;
using UnityEngine.VFX;

namespace FlowMirror
{
    // One person as the visuals see it (ADR 0001). VFXType lets VFX Graph and Custom HLSL read this
    // struct from a GraphicsBuffer; field order is the GPU layout, float4s sit on 16-byte offsets.
    [VFXType(VFXTypeAttribute.Usage.GraphicsBuffer)] //讓VFX Graph認得這個 struct
    public struct Person
    {
        public Vector2 position;
        public Vector2 velocity;
        public Vector4 colorA;
        public Vector4 colorB;
        public uint id;
    }
}
