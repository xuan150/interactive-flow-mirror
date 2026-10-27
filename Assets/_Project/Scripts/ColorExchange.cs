using System;
using System.Collections.Generic;
using UnityEngine;

namespace FlowMirror
{
    // Person-state layer, pure: each person's carried color (colorB) is pulled toward the carried colors of people
    // nearby, and slowly back to their own color (colorA). Carried colors pass along: blue that touched red brings
    // some red to the next person. Two people side by side settle on a shared middle color, never a full swap.
    public static class ColorExchange
    {
        // Each body is a capsule 6 tall and 2 wide around its center; must match BodyDistance in Silhouette.hlsl.
        const float BodyHalfLength = 2f;
        const float BodyRadius = 1f;

        /// gap: how close the two bodies must come before colors start to seep, in world units; full pull where they
        ///      touch. Same meaning as seepRadius in Silhouette.hlsl.
        /// exchangeRate: pull toward a person whose body touches, per second.
        /// returnRate: pull back toward one's own color, per second.
        public static void Step(List<Person> persons, float dt, float gap, float exchangeRate, float returnRate)
        {
            var count = persons.Count;
            // Everyone reads last frame's colors, so the result doesn't depend on list order.
            Span<Vector4> next = stackalloc Vector4[count];
            for (var i = 0; i < count; i++)
            {
                var self = persons[i];
                var sum = self.colorA * returnRate;
                var total = returnRate;
                for (var j = 0; j < count; j++)
                {
                    if (j == i) continue;
                    // Eases out like the smoothstep in Silhouette.hlsl.
                    var closeness = Mathf.SmoothStep(1f, 0f, BodyGap(self.position, persons[j].position) / gap);
                    var weight = exchangeRate * closeness;
                    sum += persons[j].colorB * weight;
                    total += weight;
                }
                // Exact step toward the weighted target with the others held still: stable at any dt.
                next[i] = total > 0f ? Vector4.Lerp(self.colorB, sum / total, 1f - Mathf.Exp(-total * dt)) : self.colorB;
            }
            for (var i = 0; i < count; i++)
            {
                var p = persons[i];
                p.colorB = next[i];
                persons[i] = p;
            }
        }

        static float BodyGap(Vector2 a, Vector2 b)
        {
            var d = a - b;
            d.y = Mathf.Max(Mathf.Abs(d.y) - 2f * BodyHalfLength, 0f);
            return Mathf.Max(d.magnitude - 2f * BodyRadius, 0f);
        }
    }
}
