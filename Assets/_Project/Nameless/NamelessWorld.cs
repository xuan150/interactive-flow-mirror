using System;
using UnityEngine;
using UnityEngine.InputSystem;

namespace FlowMirror.Nameless
{
    // The nameless world (see ADR 0002): runs the conductor, steps the particles on the GPU, draws them and the dust,
    // moves this camera, and turns the mouse into a viewer's presence. Ported from docs/lookdev/nameless.html.
    [RequireComponent(typeof(Camera))]
    public class NamelessWorld : MonoBehaviour
    {
        public enum Mode
        {
            [InspectorName("合體")] Merge,
            [InspectorName("無名生物")] Creature,
            [InspectorName("有機殼")] Shell,
        }

        [Tooltip("合體: creature and shell, and one turns into the other; the other two hold to one kind. Changing it restarts the world.")]
        [SerializeField] Mode mode = Mode.Merge;
        [Tooltip("The mouse stands in for a viewer while it is over the Game view.")]
        [SerializeField] bool mouseIsViewer = true;
        [Tooltip("Shows the event and the form in the corner (the prototype's 顯示事件).")]
        [SerializeField] bool showStatus;
        [Tooltip("Background dust motes. Each is drawn once per remembered trail frame, so many cost; the prototype had 2500.")]
        [SerializeField, Range(500, 12000)] int dustCount = 2500;
        [Tooltip("Background dust brightness; the brightest motes reach the bloom first. .28 matches the prototype's .22 through URP's ACES.")]
        [SerializeField, Range(0, 1)] float dustBrightness = .28f;
        [SerializeField] ComputeShader sim;
        [SerializeField] Shader particleShader, dustShader;

        const int Count = 512 * 384;  // particles; a multiple of NamelessSim's 256-thread groups
        const int TrailFrames = 64;    // must match NamelessDust.shader _TrailFrames
        const float DustFov = 45, DustOrbit = 3.4f;
        static readonly Bounds Everywhere = new(Vector3.zero, Vector3.one * 1000);

        Camera cam;
        Conductor conductor;
        Mode running;
        GraphicsBuffer pos, vel;
        Material particles, dust;
        int initKernel, stepKernel;

        float strength, was, dwell;
        Vector2 pointer;
        Vector3 presWorld, presOrigin, presDir = Vector3.forward;

        // the dust's remembered frames, newest first; slot 0 is the frame being drawn now
        readonly Matrix4x4[] dustView = new Matrix4x4[TrailFrames];
        readonly Vector4[] dustTW = new Vector4[TrailFrames];
        readonly float[] dustTime = new float[TrailFrames], dustSpan = new float[TrailFrames], dustK = new float[TrailFrames];
        int dustFrames;
        float dustClock; // seconds since the last frame was kept

        void OnEnable()
        {
            cam = GetComponent<Camera>();
            pos = new GraphicsBuffer(GraphicsBuffer.Target.Structured, Count, 16);
            vel = new GraphicsBuffer(GraphicsBuffer.Target.Structured, Count, 16);
            particles = new Material(particleShader);
            dust = new Material(dustShader);
            initKernel = sim.FindKernel("Init");
            stepKernel = sim.FindKernel("Step");
            foreach (int k in new[] { initKernel, stepKernel })
            {
                sim.SetBuffer(k, "_Pos", pos);
                sim.SetBuffer(k, "_Vel", vel);
            }
            sim.SetInt("_Count", Count);
            particles.SetBuffer("_Pos", pos);
            particles.SetBuffer("_Vel", vel);
            Restart();
        }

        void OnDisable()
        {
            pos?.Release();
            vel?.Release();
            Destroy(particles);
            Destroy(dust);
        }

        void Restart()
        {
            running = mode;
            conductor = new Conductor(new System.Random(), mode switch
            {
                Mode.Creature => new[] { Kind.Creature },
                Mode.Shell => new[] { Kind.Shell },
                _ => new[] { Kind.Creature, Kind.Shell },
            });
            dustFrames = 0;
            PlaceCamera(0);
            Bind(1 / 60f);
            sim.Dispatch(initKernel, Count / 256, 1, 1);
        }

        void Update()
        {
            if (mode != running) Restart();
            float dt = Mathf.Clamp(Time.deltaTime, 1e-3f, 1 / 30f);
            conductor.Update(dt);
            PlaceCamera(conductor.Time);
            UpdatePresence(dt);
            Bind(dt);
            sim.Dispatch(stepKernel, Count / 256, 1, 1);
            // this camera only: the Scene view would draw it all again
            Graphics.RenderPrimitives(new RenderParams(particles) { worldBounds = Everywhere, camera = cam }, MeshTopology.Triangles, Count * 6);
            DrawDust(dt);
        }

        void PlaceCamera(float t)
        {
            transform.position = new Vector3(Mathf.Sin(t * .05f) * .5f, -.35f + Mathf.Sin(t * .037f) * .12f, 5.2f);
            transform.LookAt(new Vector3(0, .05f, 0));
            cam.fieldOfView = 32;
            cam.nearClipPlane = .05f;
            cam.farClipPlane = 60;
        }

        // The viewer is their line of sight through the pointer, and the point where it meets the plane through the body.
        void UpdatePresence(float dt)
        {
            bool inside = false;
            if (mouseIsViewer && Application.isFocused && Mouse.current != null)
            {
                Vector2 p = Mouse.current.position.ReadValue();
                inside = p.x >= 0 && p.y >= 0 && p.x <= Screen.width && p.y <= Screen.height;
                if (inside) pointer = p;
            }
            float target = inside ? 1 : 0;
            strength = Mathf.Lerp(strength, target, 1 - Mathf.Exp(-dt * (inside ? 1.8f : 1)));
            if (strength > .5f && was <= .5f) conductor.Stimulus();
            was = strength;
            dwell = strength > .5f ? dwell + dt : Mathf.Max(0, dwell - dt * 2);
            presOrigin = transform.position;
            presDir = cam.ScreenPointToRay(pointer).direction;
            Vector3 f = transform.forward;
            float den = Vector3.Dot(presDir, f);
            if (den > 1e-3f) presWorld = presOrigin + presDir * (Vector3.Dot(conductor.Center - presOrigin, f) / den);
        }

        // Everything the simulation and the particle shader read this frame; both get the same values by name.
        void Bind(float dt)
        {
            Conductor c = conductor;
            Signals s = c.Sig;
            Form a = c.Form, b = c.Next ?? a;
            Palette next = c.PalNext ?? c.Pal;
            // a kind missing on one side keeps the other side's shape, so its half of the blend holds still
            Form ca = a.Kind == Kind.Creature ? a : b, cb = b.Kind == Kind.Creature ? b : a;
            Form sa = a.Kind == Kind.Shell ? a : b, sb = b.Kind == Kind.Shell ? b : a;

            Set("_WorldTime", c.Time); Set("_Dt", dt);
            Set("_M", s.M); Set("_Chaos", s.Chaos); Set("_Tension", s.Tension); Set("_Collapse", s.Collapse); Set("_Burst", s.Burst);
            Set("_Flash", s.Flash); Set("_Dim", s.Dim); Set("_Spread", s.Spread); Set("_Sweep", s.Sweep); Set("_Peel", s.Peel);
            Set("_SweepAxis", c.SweepAxis); Set("_PeelAxis", c.PeelAxis);
            Set("_Pulse", c.PulseAxisPos); Set("_PulseAmp", c.PulseAmp);
            Set("_Center", c.Center); Set("_Scale", c.Scale);
            sim.SetMatrix("_Rot", Matrix4x4.Rotate(c.Rotation));
            particles.SetMatrix("_Rot", Matrix4x4.Rotate(c.Rotation));
            Set("_PalA0", c.Pal.Body); Set("_PalA1", c.Pal.Hi); Set("_PalB0", next.Body); Set("_PalB1", next.Hi);
            Set("_Pres", new Vector4(presWorld.x, presWorld.y, presWorld.z, strength));
            Set("_PresO", presOrigin); Set("_PresD", presDir);
            Set("_Dwell", .15f + dwell / 10); // a few followers at once, the whole loose band after ~10 s
            Set("_ShellA", a.Kind == Kind.Shell ? 1 : 0); Set("_ShellB", b.Kind == Kind.Shell ? 1 : 0);
            Set("_Base", .088f * c.Breath * Mathf.Lerp(a.Gain, b.Gain, s.M));
            sim.SetVectorArray("_BA", ca.Blobs); sim.SetVectorArray("_BB", cb.Blobs);
            sim.SetVectorArray("_TA0", ca.T0); sim.SetVectorArray("_TA1", ca.T1);
            sim.SetVectorArray("_TB0", cb.T0); sim.SetVectorArray("_TB1", cb.T1);
            sim.SetVectorArray("_LA", sa.Lobes); sim.SetVectorArray("_LB", sb.Lobes);
            sim.SetVectorArray("_FA", sa.Folds); sim.SetVectorArray("_FB", sb.Folds);
            sim.SetVectorArray("_SA", sa.Shape); sim.SetVectorArray("_SB", sb.Shape);
        }

        void Set(string name, float v) { sim.SetFloat(name, v); particles.SetFloat(name, v); }
        void Set(string name, Vector4 v) { sim.SetVector(name, v); particles.SetVector(name, v); }
        void Set(string name, Vector3 v) => Set(name, (Vector4)v);
        void Set(string name, Color v) => Set(name, (Vector4)v);

        // The prototype faded a dust buffer by k every frame (at 60 fps) instead of clearing it; the shader redraws the
        // remembered frames weighted by the fades since, which adds up to the same streaks. Frames are kept about every
        // 1/60 s whatever the render rate, each weighted by the time it stands for, so the streaks keep the prototype's
        // length and brightness at 30 or 144 fps alike.
        void DrawDust(float dt)
        {
            if (dustClock >= 1 / 60f)
            {
                Array.Copy(dustView, 0, dustView, 1, TrailFrames - 1);
                Array.Copy(dustTime, 0, dustTime, 1, TrailFrames - 1);
                Array.Copy(dustSpan, 0, dustSpan, 1, TrailFrames - 1);
                Array.Copy(dustK, 0, dustK, 1, TrailFrames - 1);
                dustFrames = Mathf.Min(dustFrames + 1, TrailFrames - 1);
                dustClock = 0;
            }
            dustClock += dt;
            // swings across the front of the dust box instead of circling it: from behind, most motes are at its back
            float t = conductor.Time, a = .8f * Mathf.Sin(t * .043f) + .45f * Mathf.Sin(t * .071f + 1.3f);
            var eye = new Vector3(Mathf.Sin(a) * DustOrbit, .3f * Mathf.Sin(t * .05f), Mathf.Cos(a) * DustOrbit);
            // a camera's world-to-view matrix (Unity views look down -z)
            dustView[0] = Matrix4x4.Scale(new Vector3(1, 1, -1)) * Matrix4x4.TRS(eye, Quaternion.LookRotation(-eye, Vector3.up), Vector3.one).inverse;
            dustTime[0] = t;
            dustSpan[0] = dustClock;
            dustK[0] = .9f + .055f * conductor.Sig.Chaos; // per 1/60 s; longer trails while the world is smoke
            float w = 1;
            for (int i = 0; i < TrailFrames; i++)
            {
                dustTW[i] = new Vector4(dustTime[i], i <= dustFrames ? w * dustSpan[i] * 60 : 0);
                w *= Mathf.Pow(dustK[i], dustSpan[i] * 60);
            }
            dust.SetMatrixArray("_DustView", dustView);
            dust.SetVectorArray("_DustTW", dustTW);
            dust.SetVector("_PalA0", conductor.Pal.Body);
            dust.SetFloat("_DustB", dustBrightness);
            dust.SetFloat("_Motes", dustCount);
            dust.SetFloat("_FocusD", eye.magnitude);
            dust.SetFloat("_FocalRatio", Mathf.Tan(cam.fieldOfView * .5f * Mathf.Deg2Rad) / Mathf.Tan(DustFov * .5f * Mathf.Deg2Rad));
            Graphics.RenderPrimitives(new RenderParams(dust) { worldBounds = Everywhere, camera = cam }, MeshTopology.Triangles, dustCount * 6 * TrailFrames);
        }

        void OnGUI()
        {
            if (!showStatus || conductor == null) return;
            Conductor c = conductor;
            string when = c.InTransition ? $"{Mathf.RoundToInt(c.T / c.Duration * 100)}%" : $"{c.T:0.0} / {c.Duration:0.0} s";
            string form = Describe(c.Form) + (c.Next != null ? "  →  " + Describe(c.Next) : "");
            string viewer = !mouseIsViewer ? "（未開）" : strength > .5f ? $"有人在場 {dwell:0} s" : "無人";
            var style = new GUIStyle(GUI.skin.label) { fontSize = 14, normal = { textColor = new Color(.5f, .55f, .6f) } };
            GUI.Label(new Rect(16, 12, 900, 100), $"{MenuName(running)}\n事件  {c.Label}  {when}{(c.Flurry > 0 ? "  連變" : "")}\n形態  {form}\n對人  {viewer}", style);
        }

        static string Describe(Form f) => (f.Kind == Kind.Creature ? "生物 " : "") + f.Name;
        static string MenuName(Mode m) => m switch { Mode.Creature => "無名生物", Mode.Shell => "有機殼", _ => "合體" };
    }
}
