using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace FlowMirror.Nameless
{
    public enum Style { Dissolve, Morph, Partial, Implode, Rest }

    // What the shaders read from the conductor each frame; all 0 at rest except Sweep (-9 = no sweeping front).
    public struct Signals
    {
        public float M, Chaos, Collapse, Burst, Flash, Dim, Spread, Sweep, Tension, Peel;
    }

    public readonly struct Palette
    {
        public readonly float Hue;
        public readonly Color Body, Hi; // linear

        Palette(float hue, Color body, Color hi) { Hue = hue; Body = body; Hi = hi; }

        // Every change brings new colours: the hue jumps 70-170 degrees; now and then a near-grey one.
        public static Palette Next(System.Random r, Palette? prev)
        {
            float h = prev.HasValue ? prev.Value.Hue + (r.Value() < .5f ? -1 : 1) * r.Range(70, 170) : r.Range(0, 360);
            float s = r.Value() < .1f ? r.Range(.05f, .2f) : r.Range(.55f, .9f);
            return new Palette((h + 360) % 360, Hsv(h, s), Hsv(h + r.Range(-45, 45), s * .45f));
        }

        static Color Hsv(float h, float s) => Color.HSVToRGB((h % 360 + 360) % 360 / 360, s, 1).linear;
    }

    // Decides, irregularly, when and how the world changes: long-tailed holds, five transition styles that avoid
    // repeating, flurries, feints, peels and sweeps of light; and moves the body (drift, glide, wandering spin).
    // Pure C#, ported from docs/lookdev/nameless.html (class Conductor plus the life world's makeForm).
    public sealed class Conductor
    {
        static readonly Dictionary<Style, (float weight, float min, float max, string name)> Styles = new()
        {
            [Style.Dissolve] = (3, 2.8f, 5.2f, "煙散"),
            [Style.Morph] = (2.4f, 3, 6.5f, "流變"),
            [Style.Partial] = (2, 4, 8, "蛻變"),
            [Style.Implode] = (1.1f, 2.4f, 3.8f, "塌縮"),
            [Style.Rest] = (.9f, 7, 11, "散逸"),
        };
        static readonly Vector2 Roam = new(1.1f, .22f);
        public const string HoldLabel = "定形", PeelLabel = "剝落";

        sealed class Timer { public float T, Dur; }
        struct Pulse { public Vector3 Axis; public float Pos, Amp, T, Dur; public bool On; }

        readonly System.Random r;
        readonly Kind[] kinds;
        readonly List<Style> recent = new();
        Timer pre, fake, peel;
        float carry, nextPulse;
        Pulse pulse;
        Vector3 center, target, spinAxis, spinTo;
        float spinSpeed = .15f, spinToSpeed = .15f;

        public float Time { get; private set; }
        public bool InTransition { get; private set; }
        public Style Style { get; private set; }
        public float T { get; private set; } // seconds into the current hold or transition
        public float Duration { get; private set; }
        public int Flurry { get; private set; } // short holds still to come in a flurry of changes
        public string Label { get; private set; }
        public Form Form { get; private set; }
        public Form Next { get; private set; }
        public Palette Pal { get; private set; }
        public Palette? PalNext { get; private set; }
        public Signals Sig;
        public Quaternion Rotation { get; private set; } = Quaternion.identity;
        public Vector3 Center { get; private set; } // centre of the body this frame, drift included
        public float Scale { get; private set; }
        public float Breath { get; private set; } = 1;
        public Vector3 SweepAxis { get; private set; } = Vector3.up;
        public Vector3 PeelAxis { get; private set; } = Vector3.up;
        public Vector4 PulseAxisPos => new(pulse.Axis.x, pulse.Axis.y, pulse.Axis.z, pulse.Pos);
        public float PulseAmp => pulse.Amp;

        public Conductor(System.Random random, params Kind[] allowed)
        {
            r = random;
            kinds = allowed;
            spinAxis = r.Direction();
            spinTo = r.Direction();
            Form = MakeForm(null, Style.Dissolve);
            Pal = Palette.Next(r, null);
            Scale = Form.Scale;
            pulse.Axis = Vector3.up;
            nextPulse = r.Range(2, 5);
            Sig.Sweep = -9;
            EnterHold();
        }

        // A transition sometimes turns one kind into the other, the big ones (散逸, 塌縮) more often.
        Form MakeForm(Form prev, Style style)
        {
            Kind kind = prev?.Kind ?? r.Pick(kinds);
            if (prev != null && kinds.Length > 1 && r.Value() < (style is Style.Rest or Style.Implode ? .6f : .25f))
                kind = kinds.First(k => k != kind);
            return kind == Kind.Shell ? Forms.Shell(r) : Forms.Creature(r, prev?.Kind == Kind.Creature ? prev : null);
        }

        void EnterHold()
        {
            InTransition = false;
            T = 0;
            Duration = HoldDuration();
            Label = HoldLabel;
        }

        // Long-tailed (lognormal around 4.5 s), and now and then a flurry of 1-3 short holds in a row.
        float HoldDuration()
        {
            if (Flurry > 0) { Flurry--; return r.Range(.5f, 1.6f); }
            if (r.Value() < .12f) Flurry = r.RangeInclusive(1, 3);
            return Mathf.Clamp(Mathf.Exp(Mathf.Log(4.5f) + r.Normal() * .55f), 1.2f, 15);
        }

        // Never the style just used, and a style used often lately gets rarer.
        Style PickStyle()
        {
            Style? last = recent.Count > 0 ? recent[^1] : null;
            var ws = Styles.Select(kv => (s: kv.Key, w: kv.Key == last ? 0 : kv.Value.weight / (1 + 1.5f * recent.Count(x => x == kv.Key)))).ToList();
            float x = r.Value() * ws.Sum(e => e.w);
            foreach (var (s, w) in ws)
                if ((x -= w) <= 0) return s;
            return Style.Dissolve;
        }

        public void StartTransition(Style? forced = null)
        {
            Style = forced ?? PickStyle();
            recent.Add(Style);
            if (recent.Count > 5) recent.RemoveAt(0);
            Next = MakeForm(Form, Style);
            PalNext = Palette.Next(r, Pal);
            var st = Styles[Style];
            Duration = r.Range(st.min, st.max) * (Flurry > 0 ? .7f : 1);
            SweepAxis = r.Direction();
            target = new Vector3(r.Range(-1, 1) * Roam.x, r.Range(-1, 1) * Roam.y, 0);
            InTransition = true;
            T = 0;
            Label = st.name;
        }

        void Commit()
        {
            Form = Next;
            Pal = PalNext.Value;
            Next = null;
            PalNext = null;
            EnterHold();
        }

        // Creative hook for people: a viewer's arrival can cut a hold short or send a sweep of light.
        public void Stimulus()
        {
            if (InTransition || pre != null || T < .6f) return;
            if (r.Value() < .65f) { pre = new Timer { Dur = r.Range(.4f, 1.1f) }; Label = "察覺"; }
            else StartPulse();
        }

        void StartPulse() => pulse = new Pulse { Axis = r.Direction(), Dur = r.Range(1.2f, 2.6f), On = true };

        public static string NameOf(Style s) => Styles[s].name;

        public void Update(float dt)
        {
            Time += dt;
            T += dt;
            Sig = new Signals { Sweep = -9 };
            if (!InTransition) UpdateHold(dt);
            if (InTransition) UpdateTransition();
            if (peel != null)
            {
                peel.T += dt;
                float x = Mathf.Min(1, peel.T / peel.Dur);
                Sig.Peel = Mathf.Pow(Mathf.Sin(Mathf.PI * x), 2);
                if (x >= 1) { peel = null; if (Label == PeelLabel) Label = HoldLabel; }
            }
            UpdatePulse(dt);
            MoveBody(dt);
        }

        void UpdateHold(float dt)
        {
            if (pre != null)
            {
                pre.T += dt;
                Sig.Tension = Ease(Mathf.Min(1, pre.T / pre.Dur));
                if (pre.T >= pre.Dur) { pre = null; carry = 1; StartTransition(); }
            }
            else if (T >= Duration)
            {
                if (r.Value() < .5f) { pre = new Timer { Dur = r.Range(.6f, 2.2f) }; Label = "蓄勢"; }
                else { carry = 0; StartTransition(); }
            }
            else
            {
                if (fake == null && peel == null && T > 1 && Duration - T > 2.5f && r.Value() < dt * .07f)
                {
                    fake = new Timer { Dur = r.Range(1.4f, 3) };
                    Label = "虛晃";
                }
                if (Form.Kind == Kind.Shell && peel == null && fake == null && T > .8f && Duration - T > 3 && r.Value() < dt * .15f)
                {
                    peel = new Timer { Dur = r.Range(2.6f, 4.5f) };
                    PeelAxis = r.Direction();
                    Label = PeelLabel;
                }
                if (fake != null)
                {
                    fake.T += dt;
                    float x = Mathf.Min(1, fake.T / fake.Dur);
                    Sig.Tension = .75f * Mathf.Pow(Mathf.Sin(Mathf.PI * x), 2);
                    if (x >= 1) { fake = null; Label = HoldLabel; }
                }
            }
            if (r.Value() < dt * .04f)
                target = new Vector3(
                    Mathf.Clamp(target.x + r.Range(-.3f, .3f), -Roam.x, Roam.x),
                    Mathf.Clamp(target.y + r.Range(-.08f, .08f), -Roam.y, Roam.y), 0);
        }

        void UpdateTransition()
        {
            float u = Mathf.Min(1, T / Duration);
            Sig.Tension = carry * (1 - Forms.Smooth(0, .25f, u));
            switch (Style)
            {
                case Style.Dissolve:
                    Sig.Chaos = Forms.Smooth(0, .38f, u) * (1 - Forms.Smooth(.62f, .96f, u));
                    Sig.M = Forms.Smooth(.42f, .78f, u);
                    Sig.Flash = .9f * Gauss(u, .86f, .07f);
                    break;
                case Style.Rest:
                    Sig.Chaos = Forms.Smooth(0, .18f, u) * (1 - Forms.Smooth(.8f, .98f, u));
                    Sig.Spread = Sig.Chaos;
                    Sig.Dim = .3f * Sig.Chaos;
                    Sig.M = Forms.Smooth(.55f, .85f, u);
                    Sig.Flash = 1.4f * Gauss(u, .93f, .04f);
                    break;
                case Style.Morph:
                    Sig.M = Ease(u);
                    Sig.Chaos = .22f * Mathf.Sin(Mathf.PI * u);
                    Sig.Flash = .3f * Mathf.Sin(Mathf.PI * u);
                    break;
                case Style.Partial:
                    Sig.Sweep = Mathf.Lerp(-.3f, 1.3f, Ease(u));
                    Sig.M = u;
                    Sig.Chaos = .05f;
                    break;
                case Style.Implode:
                {
                    const float a = .36f, h = .5f;
                    Sig.Collapse = u < a ? Ease(u / a) : u < h ? 1 : 1 - EaseOutBack((u - h) / (1 - h));
                    Sig.M = u < .43f ? 0 : 1;
                    Sig.Flash = 2.2f * Gauss(u, .47f, .05f);
                    Sig.Burst = u > h ? Mathf.Exp(-(u - h) * Duration * 6) : 0;
                    break;
                }
            }
            if (T >= Duration) Commit();
        }

        // a travelling band of light, at irregular times; a new one starts moving on the next frame
        void UpdatePulse(float dt)
        {
            if (!pulse.On)
            {
                if ((nextPulse -= dt) <= 0) StartPulse();
                return;
            }
            pulse.T += dt;
            float x = pulse.T / pulse.Dur;
            pulse.Pos = Mathf.Lerp(-.15f, 1.15f, x);
            pulse.Amp = Mathf.Sin(Mathf.PI * Mathf.Min(x, 1)) * .9f;
            if (x >= 1) { pulse.On = false; pulse.Amp = 0; nextPulse = r.Range(2.5f, 9); }
        }

        // glide toward a target, drift, rotate about a wandering axis, breathe
        void MoveBody(float dt)
        {
            float t = Time, k = 1 - Mathf.Exp(-dt * (InTransition ? .55f : .12f));
            center = Vector3.Lerp(center, target, k);
            Center = new Vector3(center.x + Mathf.Sin(t * .031f + 1.3f) * .18f * Roam.x, center.y + Mathf.Sin(t * .047f + .4f) * .25f * Roam.y, Mathf.Sin(t * .023f) * .25f);
            if (r.Value() < dt * .08f) { spinTo = r.Direction(); spinToSpeed = r.Range(.05f, .35f); }
            spinAxis = (spinAxis + (spinTo - spinAxis) * Mathf.Min(1, dt * .3f)).normalized;
            spinSpeed = Mathf.Lerp(spinSpeed, spinToSpeed, Mathf.Min(1, dt * .3f));
            Rotation = (Quaternion.AngleAxis(spinSpeed * (1 + 2 * Sig.Chaos) * dt * Mathf.Rad2Deg, spinAxis) * Rotation).normalized;
            float mScale = InTransition && Style == Style.Partial ? Ease(Mathf.Min(1, T / Duration)) : Sig.M;
            Scale = Mathf.Lerp(Form.Scale, (Next ?? Form).Scale, mScale) * (1 + .025f * Mathf.Sin(t * .83f) * Mathf.Sin(t * .37f + .5f));
            Breath = .92f + .08f * Mathf.Sin(t * .71f) * Mathf.Sin(t * .29f + 1.7f);
        }

        static float Gauss(float u, float c, float w) => Mathf.Exp(-Mathf.Pow((u - c) / w, 2));
        static float Ease(float t) => t < .5f ? 4 * t * t * t : 1 - Mathf.Pow(-2 * t + 2, 3) / 2;

        static float EaseOutBack(float t)
        {
            const float c1 = 1.70158f, c3 = c1 + 1;
            return 1 + c3 * Mathf.Pow(t - 1, 3) + c1 * Mathf.Pow(t - 1, 2);
        }
    }
}
