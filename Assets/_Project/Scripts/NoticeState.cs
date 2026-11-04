using System;

namespace FlowMirror
{
    // Tunables for NoticeState, in seconds unless noted. Default is the first-guess timeline from docs/notice.md.
    [Serializable]
    public struct NoticeSettings
    {
        /// Entry to the start of the hush; the world has not noticed yet.
        public float noticeDelay;
        /// Hush eases from 0 up to 1 over this long.
        public float hushRise;
        /// Hush stays at 1 for this long.
        public float hushHold;
        /// Hush eases from 1 back to 0 over this long; also how fast it drains once the viewer has left.
        public float hushFall;
        /// World clock speed at the hush peak (1 = normal, 0.1 = nearly stopped).
        public float hushSlow;
        /// Stay shorter than this is a pass-by: hush only.
        public float passingMax;
        /// Stay longer than this is a long stay.
        public float longAfter;
        /// Reaction from 0 to full while the viewer is there.
        public float rampTime;
        /// Afterglow length = dwell seconds * this, clamped to [afterglowMin, afterglowMax].
        public float afterglowPerDwell;
        public float afterglowMin;
        public float afterglowMax;
        /// Time constant of viewerX chasing the real position; deliberately late.
        public float viewerLag;
        /// Time constant of the wake: a second, slower shadow of the viewer. The stretch from the viewer back to it is the tail.
        /// Never quicker than viewerLag (a smaller value, or 0, behaves as viewerLag).
        public float wakeLag;
        /// Quiet weight from 0 to 1 once someone is there.
        public float quietRise;
        /// Awareness eases from 0 up to 1 over this long, once the notice delay is over; it drains over the afterglow.
        public float awareRise;

        public static NoticeSettings Default => new()
        {
            noticeDelay = 0.5f,
            hushRise = 1.5f,
            hushHold = 1.5f,
            hushFall = 2.5f,
            hushSlow = 0.25f,
            passingMax = 3f,
            longAfter = 10f,
            rampTime = 4f,
            afterglowPerDwell = 0.5f,
            afterglowMin = 1f,
            afterglowMax = 20f,
            viewerLag = 0.6f,
            wakeLag = 2.5f,
            quietRise = 5f,
            awareRise = 1f,
        };
    }

    public struct NoticeOutput
    {
        /// World clock in seconds; never decreases, runs slow during the hush.
        public float clock;
        /// 0..1 weight of the stay phase.
        public float stay;
        /// 0..1 weight of the long-stay phase.
        public float longStay;
        /// -1..1 smoothed viewer x.
        public float viewerX;
        /// -1..1 smoothed viewer y.
        public float viewerY;
        /// -1..1 wake x, y: where the viewer was a moment ago. Always on the side they came from; meets the viewer once they stop.
        public float wakeX;
        public float wakeY;
        /// 0..1 hush strength, for debugging.
        public float hush;
        /// 0..1 how strongly the world feels the viewer (the strength of the flow around them, not its size).
        public float aware;
        /// 0..1 weight of the world holding still; rises with the viewer, drains over the afterglow.
        public float quiet;
        /// Latest quiet window in world clock: idle events that start inside it are skipped. quietUntil is Forever while it is open.
        public float quietFrom;
        public float quietUntil;
        /// The window before that, so events it skipped stay skipped after a new one opens.
        public float quietFrom2;
        public float quietUntil2;
        public bool present;
    }

    // Notice layer, pure: turns "is someone there, at which x, for how long" into a few numbers that stay continuous,
    // so the world reacts late and by its own timetable instead of mirroring the viewer frame by frame.
    public sealed class NoticeState
    {
        // Keeps divisions by a zeroed setting finite.
        const float Eps = 1e-4f;
        // quietUntil of a window that has not closed yet.
        public const float Forever = 1e9f;

        NoticeSettings s;
        bool wasPresent;
        float dwell;
        // Seconds since entry, counted only until the hush starts falling; the delay is the only reader.
        float hushT;
        // Seconds spent at h = 1.
        float holdT;
        // Past the hold, or the viewer left: h only drains from here, so the hush fires once per visit.
        bool falling;
        // Linear 0..1 progress of the hush; hush is its smoothstep, so there are no corners at either end.
        float h;
        // Linear 0..1 progress of the awareness; aware is its smoothstep.
        float a;
        float afterglow;
        float clock, stay, longStay, viewerX, viewerY, wakeX, wakeY, hush;
        float quiet, quietFrom, quietUntil, quietFrom2, quietUntil2;

        public NoticeState(NoticeSettings settings)
        {
            s = settings;
            falling = true; // no visit yet, nothing to fire
        }

        // Replaceable so the timings can be tuned in the Inspector while playing; the clock and weights carry on from where they are.
        public NoticeSettings Settings { set => s = value; }

        // For callers that don't track height.
        public NoticeOutput Step(float dt, bool present, float targetX) => Step(dt, present, targetX, 0f);

        /// present: is anyone there. targetX, targetY: viewer position on screen, -1..1; only read while present.
        public NoticeOutput Step(float dt, bool present, float targetX, float targetY)
        {
            // The negated test also rejects NaN.
            if (!(dt > 0f)) return Output();

            if (present && !wasPresent)
            {
                dwell = 0f;
                hushT = 0f;
                holdT = 0f;
                // A new visit restarts the hush but keeps h, so one still draining from the last visit doesn't jump.
                falling = false;
                // Snap on entry: sliding in from the last visitor's spot would read as a ghost.
                viewerX = Clamp(targetX, -1f, 1f);
                viewerY = Clamp(targetY, -1f, 1f);
                wakeX = viewerX;
                wakeY = viewerY;
            }
            else if (!present && wasPresent)
            {
                afterglow = Clamp(dwell * s.afterglowPerDwell, s.afterglowMin, s.afterglowMax);
                // Leaving, even before the world noticed, only lets the hush drain from where it is: no rise, no jump.
                falling = true;
            }
            wasPresent = present;

            if (present)
            {
                dwell += dt;
                // The lag is the point: the world only has a rough idea of where you are.
                var follow = FollowFactor(dt, s.viewerLag);
                viewerX += (Clamp(targetX, -1f, 1f) - viewerX) * follow;
                viewerY += (Clamp(targetY, -1f, 1f) - viewerY) * follow;
                // Chases the same target on a slower clock, so it trails the viewer by itself and catches up once they stop.
                // Never quicker than the viewer's own lag, or the tail would point ahead of them.
                var wakeFollow = FollowFactor(dt, MathF.Max(s.wakeLag, s.viewerLag));
                wakeX += (Clamp(targetX, -1f, 1f) - wakeX) * wakeFollow;
                wakeY += (Clamp(targetY, -1f, 1f) - wakeY) * wakeFollow;
            }

            if (!falling) hushT += dt;
            // During the delay h only drains, which matters when re-entering mid-fall.
            if (falling || hushT <= s.noticeDelay) h = MathF.Max(h - dt / MathF.Max(s.hushFall, Eps), 0f);
            else if (h < 1f) h = MathF.Min(h + dt / MathF.Max(s.hushRise, Eps), 1f);
            else
            {
                holdT += dt;
                if (holdT >= s.hushHold) falling = true;
            }
            hush = Smooth(h);

            // Holds through the delay (so re-entering mid-drain carries on from where it is), then rises; drains once they leave.
            if (!present) a = MathF.Max(a - dt / MathF.Max(afterglow, Eps), 0f);
            else if (dwell > s.noticeDelay) a = MathF.Min(a + dt / MathF.Max(s.awareRise, Eps), 1f);

            // Slowing can't go below 0, so the clock stays monotonic.
            clock += dt * (1f + (Clamp(s.hushSlow, 0f, 1f) - 1f) * hush);

            // Weights chase their targets at a capped speed instead of jumping, so re-entering mid-afterglow
            // just changes the target and the motion stays continuous.
            var up = dt / MathF.Max(s.rampTime, Eps);
            var down = dt / MathF.Max(present ? s.rampTime : afterglow, Eps);
            stay = Approach(stay, present && dwell >= s.passingMax ? 1f : 0f, up, down);
            longStay = Approach(longStay, present && dwell >= s.longAfter ? 1f : 0f, up, down);

            // While present the target is 1, so only the rise applies; absent, down is the afterglow rate.
            quiet = Approach(quiet, present ? 1f : 0f, dt / MathF.Max(s.quietRise, Eps), down);

            // A window is open exactly while quietUntil is Forever. The afterglow keeps it open, so coming back
            // inside it continues the same window instead of cutting a new one.
            var active = present || quiet > 0f;
            if (active && quietUntil != Forever)
            {
                quietFrom2 = quietFrom;
                quietUntil2 = quietUntil;
                quietFrom = clock;
                quietUntil = Forever;
            }
            else if (!active && quietUntil == Forever) quietUntil = clock;

            return Output();
        }

        NoticeOutput Output() => new()
        {
            clock = clock,
            stay = stay,
            longStay = longStay,
            viewerX = viewerX,
            viewerY = viewerY,
            wakeX = wakeX,
            wakeY = wakeY,
            hush = hush,
            aware = Smooth(a),
            quiet = quiet,
            quietFrom = quietFrom,
            quietUntil = quietUntil,
            quietFrom2 = quietFrom2,
            quietUntil2 = quietUntil2,
            present = wasPresent,
        };

        // Share of the gap closed in one step by a follower with this time constant: exact exponential, stable at any dt. 0 lag = jump.
        static float FollowFactor(float dt, float lag) => lag > 0f ? 1f - MathF.Exp(-dt / lag) : 1f;

        static float Approach(float value, float target, float up, float down) =>
            value < target ? MathF.Min(value + up, target) : MathF.Max(value - down, target);

        // Ease in and out, same shape as Mathf.SmoothStep.
        static float Smooth(float x) => x * x * (3f - 2f * x);

        static float Clamp(float v, float lo, float hi) => MathF.Min(MathF.Max(v, lo), hi);
    }
}
