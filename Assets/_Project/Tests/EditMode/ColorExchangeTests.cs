using System.Collections.Generic;
using NUnit.Framework;
using UnityEngine;

namespace FlowMirror.Tests
{
    public class ColorExchangeTests
    {
        static readonly Vector4 Red = new(1, 0, 0, 1);
        static readonly Vector4 Green = new(0, 1, 0, 1);
        static readonly Vector4 Blue = new(0, 0, 1, 1);

        static Person At(float x, Vector4 own, Vector4 carried) =>
            new() { position = new Vector2(x, 0), colorA = own, colorB = carried };

        static void Run(List<Person> persons, float seconds)
        {
            for (var t = 0f; t < seconds; t += 0.02f) ColorExchange.Step(persons, 0.02f, 1.5f, 1f, 0.05f);
        }

        [Test]
        public void TwoPeopleSideBySide_SettleOnTheMiddleColor()
        {
            var persons = new List<Person> { At(0, Red, Red), At(1, Blue, Blue) };
            Run(persons, 30f);

            Assert.That(persons[0].colorB.x, Is.EqualTo(0.5f).Within(0.05f));
            Assert.That(persons[0].colorB.z, Is.EqualTo(0.5f).Within(0.05f));
            Assert.That(persons[1].colorB.x, Is.EqualTo(0.5f).Within(0.05f));
        }

        [Test]
        public void BodiesFartherThanGap_KeepTheirColors()
        {
            var persons = new List<Person> { At(0, Red, Red), At(5, Blue, Blue) };
            Run(persons, 10f);

            Assert.That(persons[0].colorB, Is.EqualTo(Red));
            Assert.That(persons[1].colorB, Is.EqualTo(Blue));
        }

        [Test]
        public void GapIsMeasuredBetweenBodies_NotCenters()
        {
            // Centers 4.5 apart, but bodies are 6 tall: one's feet overlap the other's head.
            var above = At(0, Blue, Blue);
            above.position = new Vector2(0, 4.5f);
            var persons = new List<Person> { At(0, Red, Red), above };
            Run(persons, 1f);

            Assert.That(persons[0].colorB.z, Is.GreaterThan(0.1f));
        }

        [Test]
        public void AlonePerson_SlowlyReturnsToOwnColor()
        {
            var persons = new List<Person> { At(0, Red, Blue) };
            Run(persons, 5f);
            Assert.That(persons[0].colorB.x, Is.InRange(0.1f, 0.4f), "still mostly blue after 5 s");

            Run(persons, 100f);
            Assert.That(persons[0].colorB.x, Is.GreaterThan(0.95f));
        }

        [Test]
        public void CarriedColor_PassesToTheNextPerson()
        {
            // Green has been carrying red; blue never met red but picks some up from green.
            var persons = new List<Person> { At(0, Green, Red), At(1, Blue, Blue) };
            ColorExchange.Step(persons, 0.5f, 1.5f, 1f, 0.05f);

            Assert.That(persons[1].colorB.x, Is.GreaterThan(0.1f));
        }
    }
}
