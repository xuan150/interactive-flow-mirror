using System;
using System.Collections.Generic;
using UnityEngine;

namespace FlowMirror.Nameless
{
    // The web prototype's random helpers over a seedable System.Random, so tests can replay a run exactly.
    public static class Rand
    {
        public static float Value(this System.Random r) => (float)r.NextDouble();
        public static float Range(this System.Random r, float a, float b) => a + r.Value() * (b - a);
        public static int RangeInclusive(this System.Random r, int a, int b) => r.Next(a, b + 1);
        public static T Pick<T>(this System.Random r, IReadOnlyList<T> list) => list[r.Next(list.Count)];

        public static float Normal(this System.Random r)
        {
            double u = 0;
            while (u == 0) u = r.NextDouble();
            return (float)(Math.Sqrt(-2 * Math.Log(u)) * Math.Cos(2 * Math.PI * r.NextDouble()));
        }

        public static Vector3 Direction(this System.Random r)
        {
            float z = r.Range(-1, 1), t = r.Range(0, 2 * Mathf.PI), s = Mathf.Sqrt(1 - z * z);
            return new Vector3(s * Mathf.Cos(t), z, s * Mathf.Sin(t));
        }

        public static void Shuffle<T>(this System.Random r, IList<T> a)
        {
            for (int i = a.Count - 1; i > 0; i--)
            {
                int j = r.Next(i + 1);
                (a[i], a[j]) = (a[j], a[i]);
            }
        }
    }
}
