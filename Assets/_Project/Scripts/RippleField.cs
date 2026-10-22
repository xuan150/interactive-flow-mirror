using System.Collections.Generic;
using UnityEngine;
using UnityEngine.VFX;

namespace FlowMirror
{
    // Field layer: ripple height field. Ripple.compute runs the wave equation on two RenderTextures that take
    // turns being read and written (ping-pong). People inject waves: a big one on entry, small ones while moving.
    [RequireComponent(typeof(PersonTracker))]
    public class RippleField : MonoBehaviour
    {
        // Fixed step so the wave behaves the same at any frame rate; several steps run per frame.
        const float StepTime = 1f / 240f;
        const int MaxStepsPerFrame = 8;
        const int MaxSources = 32;
        // The 2D wave equation blows up above ~0.707; clamp so any Wave Speed stays stable.
        const float MaxCourant = 0.7f;
        static readonly Vector2 Area = PersonTracker.Area;

        static readonly int RippleTexId = Shader.PropertyToID("RippleTex");
        static readonly int SrcId = Shader.PropertyToID("Src");
        static readonly int DstId = Shader.PropertyToID("Dst");
        static readonly int SourcesId = Shader.PropertyToID("Sources");
        static readonly int SourceCountId = Shader.PropertyToID("SourceCount");
        static readonly int SizeId = Shader.PropertyToID("Size");
        static readonly int Courant2Id = Shader.PropertyToID("Courant2");
        static readonly int DampingId = Shader.PropertyToID("Damping");
        static readonly int EdgeWidthId = Shader.PropertyToID("EdgeWidth");

        [Tooltip("Ripple.compute.")]
        [SerializeField] ComputeShader shader;
        [Tooltip("VFX objects that receive the ripple height texture as RippleTex every frame.")]
        [SerializeField] VisualEffect[] targets;
        [Tooltip("Texels of the height field. 1/4 of the 1920x960 Game view. Set before Play; the textures are made on enable.")]
        [SerializeField] Vector2Int resolution = new(480, 240);
        [Tooltip("How fast rings travel, in world units per second. Capped for stability at about 8 (480 x 240).")]
        [SerializeField] float waveSpeed = 2f;
        [Tooltip("How fast waves fade, per second. 0 = never fade.")]
        [SerializeField] float decay = 0.8f;
        [Tooltip("Size of the splash that starts a ripple, in world units.")]
        [SerializeField] float sourceRadius = 0.15f;
        [Tooltip("Splash height when a person appears.")]
        [SerializeField] float enterStrength = 0.6f;
        [Tooltip("Splash height per world unit moved. Moving people leave a wake.")]
        [SerializeField] float moveStrength = 0.1f;
        [Tooltip("Shows the height field in the top-left corner of the Game view. Crests are bright; flat and troughs are black.")]
        [SerializeField] bool showDebug = true;

        PersonTracker tracker;
        RenderTexture read;
        RenderTexture write;
        GraphicsBuffer sources;
        int kernel;
        readonly Vector4[] pending = new Vector4[MaxSources];
        int pendingCount;
        HashSet<uint> known = new();
        HashSet<uint> seen = new();
        float accumulated;

        void Awake() => tracker = GetComponent<PersonTracker>();

        void OnEnable()
        {
            kernel = shader.FindKernel("Step");
            read = CreateTexture();
            write = CreateTexture();
            sources = new GraphicsBuffer(GraphicsBuffer.Target.Structured, MaxSources, sizeof(float) * 4);
        }

        void OnDisable()
        {
            read.Release();
            write.Release();
            sources.Release();
        }

        RenderTexture CreateTexture()
        {
            var rt = new RenderTexture(resolution.x, resolution.y, 0, RenderTextureFormat.RGFloat)
            {
                enableRandomWrite = true,
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp,
            };
            rt.Create();
            var previous = RenderTexture.active;
            RenderTexture.active = rt;
            GL.Clear(false, true, Color.clear);
            RenderTexture.active = previous;
            return rt;
        }

        void Update()
        {
            CollectSources();

            accumulated += Time.deltaTime;
            var steps = Mathf.Min((int)(accumulated / StepTime), MaxStepsPerFrame);
            // Over the cap (a hitch) the field runs slow for a moment instead of piling up steps.
            accumulated = steps == MaxStepsPerFrame ? 0f : accumulated - steps * StepTime;

            var texel = Area.x / resolution.x;
            var courant = Mathf.Min(waveSpeed * StepTime / texel, MaxCourant);
            shader.SetInts(SizeId, resolution.x, resolution.y);
            shader.SetFloat(Courant2Id, courant * courant);
            shader.SetFloat(DampingId, Mathf.Exp(-decay * StepTime));
            shader.SetFloat(EdgeWidthId, 16f);
            shader.SetBuffer(kernel, SourcesId, sources);

            for (var i = 0; i < steps; i++)
            {
                // Sources go in once, on the first step. Above 240 fps a frame can have 0 steps; they wait.
                if (i == 0 && pendingCount > 0) sources.SetData(pending, 0, 0, pendingCount);
                shader.SetInt(SourceCountId, i == 0 ? pendingCount : 0);
                shader.SetTexture(kernel, SrcId, read);
                shader.SetTexture(kernel, DstId, write);
                shader.Dispatch(kernel, Mathf.CeilToInt(resolution.x / 8f), Mathf.CeilToInt(resolution.y / 8f), 1);
                (read, write) = (write, read);
            }
            if (steps > 0) pendingCount = 0;

            foreach (var vfx in targets)
                if (vfx && vfx.HasTexture(RippleTexId)) vfx.SetTexture(RippleTexId, read);
        }

        void CollectSources()
        {
            seen.Clear();
            foreach (var p in tracker.Persons)
            {
                seen.Add(p.id);
                if (!known.Contains(p.id)) AddSource(p.position, enterStrength);
                AddSource(p.position, moveStrength * p.velocity.magnitude * Time.deltaTime);
            }
            (known, seen) = (seen, known);
        }

        void AddSource(Vector2 position, float amount)
        {
            if (amount <= 0f || pendingCount >= MaxSources) return;
            var uv = (position + Area * 0.5f) / Area;
            pending[pendingCount++] = new Vector4(uv.x * resolution.x, uv.y * resolution.y,
                sourceRadius / Area.x * resolution.x, amount);
        }

        void OnGUI()
        {
            if (showDebug && read) GUI.DrawTexture(new Rect(10, 10, 360, 180), read);
        }
    }
}
