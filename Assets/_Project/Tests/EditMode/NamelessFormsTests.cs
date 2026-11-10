using System.Collections.Generic;
using System.Linq;
using FlowMirror.Nameless;
using NUnit.Framework;
using UnityEngine;

namespace FlowMirror.Tests
{
    // Ported from the web prototype's check-creature.js / check-shell.js: every form fits the frame, no kind is
    // systematically small (the "tiny over-bright knot"), and a shrunk creature is dimmed by exactly the area it lost.
    public class NamelessFormsTests
    {
        [Test]
        public void Creatures_FitTheFrame_AndKeepTheirMass()
        {
            var r = new System.Random(1);
            var massByKind = new Dictionary<string, List<float>>();
            Form prev = null;
            for (int i = 0; i < 3000; i++)
            {
                Form f = prev = Forms.Creature(r, prev);
                float area = 0, ext = 0, tip = 0;
                foreach (Vector4 b in f.Blobs.Where(b => b.w > 0))
                {
                    area += b.w * b.w;
                    ext = Mathf.Max(ext, ((Vector3)b).magnitude + b.w);
                }
                for (int j = 0; j < 4; j++)
                    if (f.T0[j].w > 0) tip = Mathf.Max(tip, ((Vector3)f.T1[j]).magnitude);

                Assert.That(ext, Is.LessThanOrEqualTo(1.15f + 1e-4f), $"{f.Name} body leaves the frame");
                Assert.That(tip, Is.LessThanOrEqualTo(1.6f + 1e-4f), $"{f.Name} tendril leaves the frame");
                Assert.That(area, Is.LessThanOrEqualTo(Forms.CreatureArea + 1e-4f), $"{f.Name} heavier than the target mass");
                Assert.That(f.Gain, Is.EqualTo(Mathf.Max(Forms.CreatureGainFloor, area / Forms.CreatureArea)).Within(1e-3f), $"{f.Name} gain does not match its area");
                if (!massByKind.TryGetValue(f.Name, out var list)) massByKind[f.Name] = list = new List<float>();
                list.Add(area / Forms.CreatureArea);
            }
            Assert.That(massByKind.Count, Is.EqualTo(5), "every creature kind appears");
            foreach (var (kind, masses) in massByKind)
                Assert.That(Median(masses), Is.GreaterThanOrEqualTo(.6f), $"{kind} is systematically small");
        }

        // The fit samples 400 random directions; check it against a dense sampling of the true outline.
        [Test]
        public void Shells_FitTheSameFrameAsCreatures()
        {
            var r = new System.Random(2);
            var check = new System.Random(3);
            var reach = new List<float>();
            for (int i = 0; i < 400; i++)
            {
                Form f = Forms.Shell(r);
                reach.Add(Forms.Extent(f, 6000, check) * f.Scale * (1 + f.Shape[2].w));
            }
            Assert.That(reach.Max(), Is.LessThanOrEqualTo(1.25f), "a shell overshoots the creature frame");
            Assert.That(Median(reach), Is.GreaterThanOrEqualTo(.85f), "shells are systematically small");
        }

        static float Median(List<float> a)
        {
            var s = a.OrderBy(x => x).ToList();
            return s[(s.Count - 1) / 2];
        }
    }
}
