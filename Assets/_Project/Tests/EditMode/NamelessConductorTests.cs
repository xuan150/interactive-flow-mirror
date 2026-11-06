using System.Collections.Generic;
using System.Linq;
using FlowMirror.Nameless;
using NUnit.Framework;
using UnityEngine;

namespace FlowMirror.Tests
{
    // The conductor must stay unpredictable (no regular rhythm a viewer grasps quickly) while respecting the mode.
    public class NamelessConductorTests
    {
        const float Dt = 1 / 60f;

        sealed class Run
        {
            public readonly List<Style> Styles = new();
            public readonly List<float> Holds = new();
            public readonly HashSet<Kind> Kinds = new();
            public bool PeelOnCreature, KindChangedMidMorph;
        }

        static Run Play(float minutes, int seed, params Kind[] kinds)
        {
            var c = new Conductor(new System.Random(seed), kinds);
            var run = new Run();
            bool wasTransition = false;
            float holdStart = 0;
            for (float t = 0; t < minutes * 60; t += Dt)
            {
                c.Update(Dt);
                if (c.InTransition && !wasTransition)
                {
                    run.Styles.Add(c.Style);
                    run.Holds.Add(c.Time - holdStart);
                }
                if (!c.InTransition && wasTransition) holdStart = c.Time;
                wasTransition = c.InTransition;
                run.Kinds.Add(c.Form.Kind);
                if (c.Sig.Peel > 0 && c.Form.Kind != Kind.Shell) run.PeelOnCreature = true;
                if (c.Next != null && c.Next.Kind != c.Form.Kind && c.Style == Style.Morph) run.KindChangedMidMorph = true;
            }
            return run;
        }

        [Test]
        public void NeverRepeatsATransitionStyleBackToBack()
        {
            var run = Play(30, 1, Kind.Creature, Kind.Shell);
            Assert.That(run.Styles.Count, Is.GreaterThan(100));
            for (int i = 1; i < run.Styles.Count; i++) Assert.That(run.Styles[i], Is.Not.EqualTo(run.Styles[i - 1]));
            Assert.That(run.Styles.Distinct().Count(), Is.EqualTo(5), "all five styles appear");
        }

        // Holds (feint and lead-in included) are long-tailed and bounded: flurries under 2 s, never past ~17 s.
        [Test]
        public void HoldsAreIrregular_AndBounded()
        {
            var holds = Play(30, 2, Kind.Creature, Kind.Shell).Holds.Skip(1).ToList();
            Assert.That(holds.Min(), Is.GreaterThanOrEqualTo(.5f - 1e-3f));
            Assert.That(holds.Max(), Is.LessThanOrEqualTo(15 + 2.2f + .1f));
            Assert.That(holds.Count(h => h < 1.6f), Is.GreaterThan(0), "flurries of short holds happen");
            float mean = holds.Average(), sd = Mathf.Sqrt(holds.Average(h => (h - mean) * (h - mean)));
            Assert.That(sd / mean, Is.GreaterThan(.35f), "hold lengths vary enough not to read as a beat");
        }

        [Test]
        public void SingleKindModes_KeepToTheirKind()
        {
            Assert.That(Play(15, 3, Kind.Creature).Kinds, Is.EquivalentTo(new[] { Kind.Creature }));
            Assert.That(Play(15, 4, Kind.Shell).Kinds, Is.EquivalentTo(new[] { Kind.Shell }));
        }

        [Test]
        public void Merge_TurnsOneKindIntoTheOther_EvenMidMorph()
        {
            var run = Play(30, 5, Kind.Creature, Kind.Shell);
            Assert.That(run.Kinds, Is.EquivalentTo(new[] { Kind.Creature, Kind.Shell }));
            Assert.That(run.KindChangedMidMorph, Is.True, "a creature can slowly harden into a shell");
        }

        [Test]
        public void OnlyShellsPeel()
        {
            Assert.That(Play(30, 6, Kind.Creature, Kind.Shell).PeelOnCreature, Is.False);
        }
    }
}
