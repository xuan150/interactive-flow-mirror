using System.Collections.Generic;
using UnityEngine;

namespace FlowMirror.Nameless
{
    public enum Kind { Creature, Shell }

    // One shape the body can take. A creature fills Blobs/T0/T1 (metaballs and tendrils), a shell fills Lobes/Folds/Shape;
    // NamelessSim.compute reads them as uniform arrays, so the array lengths must match its _BA/_TA0/_LA/_FA/_SA sizes.
    public sealed class Form
    {
        public Kind Kind;
        public string Name;
        public float Scale, Gain;
        public readonly Vector4[] Blobs = new Vector4[8], T0 = new Vector4[4], T1 = new Vector4[4];
        public readonly Vector4[] Lobes = new Vector4[5], Folds = new Vector4[2], Shape = new Vector4[3];
        internal string Variety; // the creature kind, so the next creature rarely repeats it
    }

    // Ported 1:1 from docs/lookdev/nameless.html (makeCreature, makeShell).
    public static class Forms
    {
        public const float CreatureArea = .6f; // every creature is scaled to this sum of r^2: same mass, same brightness
        public const float CreatureGainFloor = .55f; // a stretched-out form dims by its lost area, but never so far it reads as sparse
        public const float ShellGain = .35f; // dimmer than the creature so its sweep of light stands out

        static readonly (string key, string name)[] CreatureKinds =
            { ("cluster", "團簇"), ("spine", "脊列"), ("bud", "出芽"), ("colony", "群落"), ("pair", "雙生") };

        public static Form Creature(System.Random r, Form prev)
        {
            (string key, string name) kind;
            do kind = r.Pick(CreatureKinds); while (prev != null && kind.key == prev.Variety && r.Value() < .85f);

            var blobs = new List<Vector4>();
            void B(Vector3 c, float rad) => blobs.Add(new Vector4(c.x, c.y, c.z, rad));
            switch (kind.key)
            {
                case "cluster":
                    for (int i = r.RangeInclusive(3, 6); i-- > 0;) B(r.Direction() * r.Range(0, .45f), r.Range(.26f, .48f));
                    break;
                case "spine":
                {
                    Vector3 p = Vector3.zero, d = r.Direction();
                    int n = r.RangeInclusive(4, 7);
                    for (int i = 0; i < n; i++)
                    {
                        B(p, r.Range(.18f, .36f) * (1 - i / (float)n * .4f));
                        d = (d + r.Direction() * .8f).normalized;
                        p += d * r.Range(.24f, .34f);
                    }
                    break;
                }
                case "bud":
                    B(Vector3.zero, r.Range(.5f, .66f));
                    for (int i = r.RangeInclusive(2, 5); i-- > 0;) B(r.Direction() * r.Range(.55f, .78f), r.Range(.13f, .28f));
                    break;
                case "colony":
                    for (int i = r.RangeInclusive(5, 8); i-- > 0;) B(r.Direction() * r.Range(.3f, .85f), r.Range(.15f, .28f));
                    break;
                default: // pair
                {
                    Vector3 d = r.Direction();
                    float g = r.Range(.5f, .8f);
                    B(d * (-g * .5f), r.Range(.38f, .52f));
                    B(d * (g * .5f), r.Range(.18f, .3f));
                    break;
                }
            }

            var tends = new List<(Vector3 a, Vector3 b, float rad, float wobble)>();
            for (int i = kind.key == "colony" ? r.RangeInclusive(2, 4) : r.RangeInclusive(0, 3); i-- > 0;)
            {
                Vector3 a, b;
                if (kind.key == "colony")
                {
                    var pair = new List<Vector4>(blobs);
                    r.Shuffle(pair);
                    a = pair[0]; b = pair[1];
                }
                else
                {
                    Vector4 s = r.Pick(blobs);
                    a = s;
                    b = a + r.Direction() * (s.w + r.Range(.35f, .85f));
                }
                tends.Add((a, b, r.Range(.04f, .075f), r.Range(.3f, 1f)));
            }

            // centre on the heavy blobs, then size by mass (surface ~ sum r^2) and shrink only to fit the frame
            float ws = 0;
            Vector3 c = Vector3.zero;
            foreach (Vector4 b in blobs) { float w = b.w * b.w * b.w; ws += w; c += (Vector3)b * w; }
            c /= ws;
            float ext = 0, tip = 0, area = 0;
            for (int i = 0; i < blobs.Count; i++)
            {
                Vector4 b = blobs[i];
                Vector3 p = (Vector3)b - c;
                blobs[i] = new Vector4(p.x, p.y, p.z, b.w);
                ext = Mathf.Max(ext, p.magnitude + b.w);
                area += b.w * b.w;
            }
            for (int i = 0; i < tends.Count; i++)
            {
                var t = tends[i];
                tends[i] = (t.a - c, t.b - c, t.rad, t.wobble);
                tip = Mathf.Max(tip, (t.b - c).magnitude);
            }
            float k = Mathf.Min(Mathf.Sqrt(CreatureArea / area), 1.15f / ext, 1.6f / Mathf.Max(tip, 1e-3f));

            var f = new Form { Kind = Kind.Creature, Variety = kind.key, Name = kind.name };
            var slots = new List<int> { 0, 1, 2, 3, 4, 5, 6, 7 };
            r.Shuffle(slots);
            for (int i = 0; i < blobs.Count; i++) f.Blobs[slots[i]] = blobs[i] * k;
            for (int i = 0; i < tends.Count; i++)
            {
                var t = tends[i];
                f.T0[i] = new Vector4(t.a.x * k, t.a.y * k, t.a.z * k, t.rad * k);
                f.T1[i] = new Vector4(t.b.x * k, t.b.y * k, t.b.z * k, t.wobble);
            }
            f.Scale = r.Range(.8f, 1f);
            // a shrunk form is dimmed by its lost area since the same particles crowd onto less surface
            f.Gain = Mathf.Clamp(area * k * k / CreatureArea, CreatureGainFloor, 1);
            return f;
        }

        public static Form Shell(System.Random r)
        {
            int nl = r.RangeInclusive(1, 5), nf = r.RangeInclusive(1, 2);
            bool cav = r.Value() < .5f, tw = r.Value() < .55f;
            var f = new Form { Kind = Kind.Shell, Gain = ShellGain };
            for (int i = 0; i < nl; i++)
            {
                Vector3 a = r.Direction() * r.Range(3, 16);
                f.Lobes[i] = new Vector4(a.x, a.y, a.z, r.Value() < .25f ? r.Range(-.35f, -.12f) : r.Range(.2f, .85f));
            }
            for (int i = 0; i < nf; i++)
            {
                Vector3 a = r.Direction() * r.Range(1.5f, 6);
                f.Folds[i] = new Vector4(a.x, a.y, a.z, r.Range(.03f, .13f));
            }
            f.Shape[0] = new Vector4(r.Range(.6f, 1.35f), r.Range(.65f, 1.5f), r.Range(.6f, 1.35f), tw ? r.Range(.6f, 2.4f) * (r.Value() < .5f ? -1 : 1) : 0);
            Vector3 cd = r.Direction();
            f.Shape[1] = new Vector4(cd.x, cd.y, cd.z, r.Range(.05f, .65f));
            f.Shape[2] = new Vector4(cav ? r.Range(.15f, .6f) : 1, r.Range(.04f, .16f), r.Range(.8f, 2.4f), r.Range(.003f, .035f));
            var tags = new List<string> { $"葉瓣×{nl}", "皺褶" };
            if (cav) tags.Add("凹陷");
            if (tw) tags.Add("扭轉");
            f.Name = "殼 " + string.Join("·", tags);
            f.Scale = r.Range(.85f, 1.1f) / Extent(f, 400, r);
            return f;
        }

        // The shell's largest reach, sampled over random directions plus every lobe's own axis (a narrow lobe slips
        // between random samples). Lobes are taken at their full swell (1.35x, or .65x for dents), folds and noise at peak.
        public static float Extent(Form f, int directions, System.Random r)
        {
            float mx = 0;
            for (int i = 0; i < directions + f.Lobes.Length; i++)
            {
                Vector3 d = i < directions ? r.Direction() : ((Vector3)f.Lobes[i - directions]).normalized;
                if (d == Vector3.zero) continue;
                float rad = 1;
                foreach (Vector4 l in f.Lobes)
                {
                    float kk = ((Vector3)l).magnitude;
                    if (kk > 1e-3f) rad += l.w * (l.w > 0 ? 1.35f : .65f) * Mathf.Pow(Mathf.Max(Vector3.Dot(d, l) / kk, 0), kk);
                }
                rad += f.Folds[0].w + f.Folds[1].w + f.Shape[2].y;
                rad *= Mathf.Lerp(1, f.Shape[2].x, Smooth(f.Shape[1].w, f.Shape[1].w + .3f, Vector3.Dot(d, f.Shape[1])));
                mx = Mathf.Max(mx, Vector3.Scale(d * rad, f.Shape[0]).magnitude);
            }
            return mx;
        }

        internal static float Smooth(float a, float b, float x)
        {
            float t = Mathf.Clamp01((x - a) / (b - a));
            return t * t * (3 - 2 * t);
        }
    }
}
