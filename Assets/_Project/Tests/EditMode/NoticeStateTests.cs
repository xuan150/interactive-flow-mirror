using NUnit.Framework;

namespace FlowMirror.Tests
{
    public class NoticeStateTests
    {
        const float Dt = 0.02f;
        static readonly NoticeSettings Cfg = NoticeSettings.Default;

        static NoticeState NewState() => new(Cfg);

        // Largest hush change in one step while h moves linearly over `seconds`: smoothstep is at most 1.5x as steep, plus float slack.
        static float MaxStep(float seconds) => Dt / seconds * 1.5f + 1e-4f;

        // Counts steps instead of summing floats, so every run has the same length.
        static NoticeOutput Run(NoticeState state, float seconds, bool present, float x = 0f, float y = 0f)
        {
            var o = default(NoticeOutput);
            var steps = (int)(seconds / Dt + 0.5f);
            for (var i = 0; i < steps; i++) o = state.Step(Dt, present, x, y);
            return o;
        }

        static NoticeOutput[] Trace(NoticeState state, float seconds, bool present)
        {
            var trace = new NoticeOutput[(int)(seconds / Dt + 0.5f)];
            for (var i = 0; i < trace.Length; i++) trace[i] = state.Step(Dt, present, 0f);
            return trace;
        }

        // The viewer has just left with `before` showing: the hush must start down on that very step, never turn up, end at 0, and never jump.
        static void AssertDrainsToZero(NoticeState state, float before)
        {
            var maxDrop = MaxStep(Cfg.hushFall);
            var prev = before;
            for (var i = 0; i < 200; i++) // 4 s, longer than hushFall
            {
                var hush = state.Step(Dt, false, 0f).hush;
                Assert.That(prev - hush, Is.InRange(-1e-6f, maxDrop), $"step {i}");
                if (i == 0) Assert.That(hush, Is.LessThan(before), "starts down on the step it leaves");
                prev = hush;
            }

            Assert.That(prev, Is.EqualTo(0f));
        }

        [Test]
        public void NoOneThere_EverythingIsZeroAndClockRunsAtNormalSpeed()
        {
            var o = Run(NewState(), 5f, false);

            Assert.That(o.present, Is.False);
            Assert.That(o.stay, Is.EqualTo(0f));
            Assert.That(o.longStay, Is.EqualTo(0f));
            Assert.That(o.hush, Is.EqualTo(0f));
            Assert.That(o.clock, Is.EqualTo(5f).Within(0.001f));
        }

        [Test]
        public void NoticeDelay_NothingReactsYet()
        {
            var state = NewState();
            var o = default(NoticeOutput);
            for (var i = 0; i < 20; i++) // 0.4 s, inside the 0.5 s delay
            {
                o = state.Step(Dt, true, 0f);
                Assert.That(o.hush, Is.EqualTo(0f));
            }

            Assert.That(o.present, Is.True);
            Assert.That(o.clock, Is.EqualTo(0.4f).Within(0.001f));
        }

        [Test]
        public void Hush_RisesGradually_ReachingOneAfterDelayPlusRise()
        {
            var state = NewState();
            var maxRise = MaxStep(Cfg.hushRise);
            var prev = 0f;
            var reachedAt = -1f;
            for (var i = 0; i < 125; i++) // 2.5 s
            {
                var o = state.Step(Dt, true, 0f);
                Assert.That(o.hush - prev, Is.InRange(-1e-6f, maxRise), $"step {i}");
                if (reachedAt < 0f && o.hush >= 0.9999f) reachedAt = (i + 1) * Dt;
                prev = o.hush;
            }

            Assert.That(reachedAt, Is.EqualTo(Cfg.noticeDelay + Cfg.hushRise).Within(3 * Dt));
        }

        [Test]
        public void Hush_ClockSlowsSmoothlyDownToHushSlow()
        {
            var state = NewState();
            // Speed is 1 + (hushSlow - 1) * hush, so it changes by at most this much per step.
            var maxChange = (1f - Cfg.hushSlow) * Dt / Cfg.hushRise * 1.5f + 1e-3f;
            var prevClock = 0f;
            var prevSpeed = 1f;
            for (var i = 0; i < 125; i++) // 2.5 s, on the plateau
            {
                var o = state.Step(Dt, true, 0f);
                var speed = (o.clock - prevClock) / Dt;
                Assert.That(System.Math.Abs(speed - prevSpeed), Is.LessThan(maxChange), $"step {i}");
                prevClock = o.clock;
                prevSpeed = speed;
            }

            Assert.That(prevSpeed, Is.EqualTo(Cfg.hushSlow).Within(0.001f));
        }

        [Test]
        public void Hush_HoldsAtOne_ForAboutHushHold()
        {
            var held = 0;
            foreach (var o in Trace(NewState(), 7f, true))
                if (o.hush >= 1f) held++;

            Assert.That(held * Dt, Is.EqualTo(Cfg.hushHold).Within(3 * Dt));
        }

        [Test]
        public void Hush_FallsGradually_OverAboutHushFall_NeverUpAgain()
        {
            var maxDrop = MaxStep(Cfg.hushFall);
            var peaked = false;
            var start = -1;
            var end = -1;
            var prev = 0f;
            var trace = Trace(NewState(), 7f, true);
            for (var i = 0; i < trace.Length; i++)
            {
                var hush = trace[i].hush;
                if (hush >= 1f) peaked = true;
                else if (peaked)
                {
                    if (start < 0) start = i;
                    if (end < 0 && hush <= 0f) end = i;
                    Assert.That(prev - hush, Is.InRange(-1e-6f, maxDrop), $"step {i}");
                }
                prev = hush;
            }

            Assert.That(start, Is.GreaterThan(0), "it peaked and then started to fall");
            Assert.That(end, Is.GreaterThan(start), "it reached 0");
            Assert.That((end - start + 1) * Dt, Is.EqualTo(Cfg.hushFall).Within(3 * Dt));
        }

        [Test]
        public void Hush_ClockRunsAtHushSlowAtThePeak_ThenBackToNormalSpeedAfterTheFall()
        {
            var state = NewState();
            // 2.5 s: past delay + rise (2.0 s), before the hold ends (3.5 s).
            var before = Run(state, 2.5f, true);
            var peak = state.Step(Dt, true, 0f);
            Assert.That(peak.hush, Is.EqualTo(1f).Within(0.001f));
            Assert.That(peak.clock - before.clock, Is.EqualTo(Dt * Cfg.hushSlow).Within(0.0001f));

            // Delay + rise + hold + fall = 6.0 s; this is 7.02 s.
            var after = Run(state, 4.5f, true);
            var next = state.Step(Dt, true, 0f);
            Assert.That(next.hush, Is.EqualTo(0f));
            Assert.That(next.clock - after.clock, Is.EqualTo(Dt).Within(0.0001f));
        }

        [Test]
        public void Hush_HappensOnlyOncePerVisit()
        {
            var state = NewState();
            Run(state, 7f, true); // the whole hush is over by 6.0 s

            for (var i = 0; i < 400; i++) // 8 more seconds, still standing there
                Assert.That(state.Step(Dt, true, 0f).hush, Is.EqualTo(0f));
        }

        [Test]
        public void LeavingDuringTheRise_DrainsAtOnce_NeverRisesAgain()
        {
            var state = NewState();
            var before = Run(state, 1.2f, true).hush; // 0.7 s into the 1.5 s rise
            Assert.That(before, Is.InRange(0.1f, 0.9f));

            AssertDrainsToZero(state, before);
        }

        [Test]
        public void LeavingDuringTheHold_DrainsAtOnce()
        {
            var state = NewState();
            var before = Run(state, 2.8f, true).hush; // hold runs 2.0 s to 3.5 s
            Assert.That(before, Is.EqualTo(1f));

            AssertDrainsToZero(state, before);
        }

        [Test]
        public void ReenteringDuringTheFall_DrainsThroughTheDelay_ThenRisesAgain_WithoutJumps()
        {
            var state = NewState();
            Run(state, 2.8f, true); // on the plateau
            var prev = Run(state, 1f, false).hush; // 1 s into the fall: h = 1 - 1 / 2.5 = 0.6
            Assert.That(prev, Is.InRange(0.5f, 0.8f));

            var maxDrop = MaxStep(Cfg.hushFall);
            var maxRise = MaxStep(Cfg.hushRise);
            var peak = 0f;
            for (var i = 0; i < 400; i++) // 8 s: delay, rise, hold, fall
            {
                var hush = state.Step(Dt, true, 0f).hush;
                Assert.That(prev - hush, Is.InRange(-maxRise, maxDrop), $"step {i}");
                if (i < 23) Assert.That(hush, Is.LessThanOrEqualTo(prev + 1e-6f), "no rise inside the new 0.5 s delay");
                peak = System.Math.Max(peak, hush);
                prev = hush;
            }

            Assert.That(peak, Is.GreaterThan(0.99f), "the new visit gets its own hush");
            Assert.That(prev, Is.EqualTo(0f));
        }

        [Test]
        public void LeavingBeforeTheNoticeDelay_NeverHushes()
        {
            var state = NewState();
            var peak = 0f;
            for (var i = 0; i < 15; i++) peak = System.Math.Max(peak, state.Step(Dt, true, 0f).hush); // 0.3 s
            for (var i = 0; i < 250; i++) peak = System.Math.Max(peak, state.Step(Dt, false, 0f).hush);

            Assert.That(peak, Is.EqualTo(0f));
        }

        [Test]
        public void PassingBy_OnlyHushes_StayStaysZero()
        {
            var state = NewState();
            var peak = 0f;
            for (var i = 0; i < 125; i++) // 2.5 s, shorter than passingMax but past the rise (2.0 s)
            {
                var o = state.Step(Dt, true, 0f);
                peak = System.Math.Max(peak, o.hush);
                Assert.That(o.stay, Is.EqualTo(0f));
                Assert.That(o.longStay, Is.EqualTo(0f));
            }
            for (var i = 0; i < 250; i++)
            {
                var o = state.Step(Dt, false, 0f);
                Assert.That(o.stay, Is.EqualTo(0f));
                Assert.That(o.longStay, Is.EqualTo(0f));
            }

            Assert.That(peak, Is.GreaterThan(0.99f), "the hush still happened");
        }

        [Test]
        public void Stay_RisesToOneOverRampTime_AfterPassingMax()
        {
            var state = NewState();
            Assert.That(Run(state, 2.9f, true).stay, Is.EqualTo(0f));

            // 5 s: two seconds into a 4 s ramp that started at 3 s.
            var half = Run(state, 2.1f, true);
            Assert.That(half.stay, Is.EqualTo(0.5f).Within(0.02f));
            Assert.That(half.longStay, Is.EqualTo(0f));

            Assert.That(Run(state, 2.1f, true).stay, Is.EqualTo(1f).Within(0.001f));
        }

        [Test]
        public void LongStay_RisesToOneOverRampTime_AfterLongAfter()
        {
            var state = NewState();
            var o = Run(state, 9.9f, true);
            Assert.That(o.longStay, Is.EqualTo(0f));
            Assert.That(o.stay, Is.EqualTo(1f).Within(0.001f));

            // 12 s: two seconds into the ramp that started at 10 s.
            Assert.That(Run(state, 2.1f, true).longStay, Is.EqualTo(0.5f).Within(0.02f));
            Assert.That(Run(state, 2.1f, true).longStay, Is.EqualTo(1f).Within(0.001f));
        }

        [TestCase(20f, 10f)] // afterglow = dwell * 0.5
        [TestCase(60f, 20f)] // 30 s would be longer than afterglowMax
        public void Afterglow_LengthFollowsDwell_CappedByMax(float dwell, float afterglow)
        {
            var state = NewState();
            Run(state, dwell, true);

            var half = Run(state, afterglow / 2f, false);
            Assert.That(half.stay, Is.EqualTo(0.5f).Within(0.03f));
            Assert.That(half.longStay, Is.EqualTo(0.5f).Within(0.03f));

            Assert.That(Run(state, afterglow / 2f - 0.5f, false).stay, Is.GreaterThan(0f), "not gone 0.5 s early");

            var end = Run(state, 1f, false);
            Assert.That(end.stay, Is.EqualTo(0f));
            Assert.That(end.longStay, Is.EqualTo(0f));
        }

        [Test]
        public void Afterglow_StayOnlyGoesDown()
        {
            var state = NewState();
            Run(state, 20f, true);

            var prevStay = 1f;
            var prevLong = 1f;
            for (var i = 0; i < 800; i++) // 16 s, longer than the 10 s afterglow
            {
                var o = state.Step(Dt, false, 0f);
                Assert.That(o.stay, Is.LessThanOrEqualTo(prevStay));
                Assert.That(o.longStay, Is.LessThanOrEqualTo(prevLong));
                prevStay = o.stay;
                prevLong = o.longStay;
            }

            Assert.That(prevStay, Is.EqualTo(0f));
        }

        [Test]
        public void Clock_NeverDecreases()
        {
            var state = NewState();
            var prev = 0f;
            for (var i = 0; i < 4000; i++)
            {
                var dt = 0.01f + (i % 5) * 0.01f; // uneven frames
                var present = (i / 300) % 2 == 0;  // in and out, several visits
                var o = state.Step(dt, present, 0f);
                Assert.That(o.clock, Is.GreaterThanOrEqualTo(prev));
                prev = o.clock;
            }
        }

        [Test]
        public void ViewerX_StartsAtTargetOnEntry_ThenLagsBehind()
        {
            var state = NewState();
            Run(state, 1f, false);

            Assert.That(state.Step(Dt, true, 0.8f).viewerX, Is.EqualTo(0.8f));

            // Target jumps to the other side. After 0.3 s of a 0.6 s time constant it is about 0.17, nowhere near -0.8.
            Assert.That(Run(state, 0.3f, true, -0.8f).viewerX, Is.InRange(0.1f, 0.25f));
            Assert.That(Run(state, 6f, true, -0.8f).viewerX, Is.EqualTo(-0.8f).Within(0.01f));
        }

        [Test]
        public void ViewerX_HoldsAfterLeaving_AndSnapsAgainOnReentry()
        {
            var state = NewState();
            var last = Run(state, 5f, true, 0.5f).viewerX;

            Assert.That(Run(state, 2f, false, -1f).viewerX, Is.EqualTo(last));
            Assert.That(state.Step(Dt, true, -0.9f).viewerX, Is.EqualTo(-0.9f));
        }

        [Test]
        public void ViewerY_StartsAtTargetOnEntry_ThenLagsBehind()
        {
            var state = NewState();
            Run(state, 1f, false);

            Assert.That(state.Step(Dt, true, 0f, 0.8f).viewerY, Is.EqualTo(0.8f));

            // Same time constant as x: after 0.3 s it is about 0.17, nowhere near -0.8.
            Assert.That(Run(state, 0.3f, true, 0f, -0.8f).viewerY, Is.InRange(0.1f, 0.25f));
            Assert.That(Run(state, 6f, true, 0f, -0.8f).viewerY, Is.EqualTo(-0.8f).Within(0.01f));
        }

        [Test]
        public void ViewerY_HoldsAfterLeaving_AndSnapsAgainOnReentry()
        {
            var state = NewState();
            var last = Run(state, 5f, true, 0f, 0.5f).viewerY;

            Assert.That(Run(state, 2f, false, 0f, -1f).viewerY, Is.EqualTo(last));
            Assert.That(state.Step(Dt, true, 0f, -0.9f).viewerY, Is.EqualTo(-0.9f));
        }

        [TestCase(3f, 1f)]
        [TestCase(-3f, -1f)]
        public void ViewerY_ClampedToUnitRange(float target, float expected)
        {
            Assert.That(NewState().Step(Dt, true, 0f, target).viewerY, Is.EqualTo(expected), "on entry");

            var state = NewState();
            state.Step(Dt, true, 0f, 0f);
            Assert.That(Run(state, 6f, true, 0f, target).viewerY, Is.EqualTo(expected).Within(0.01f), "while following");
        }

        [Test]
        public void StepWithoutY_KeepsViewerYAtZero()
        {
            var state = NewState();
            var o = default(NoticeOutput);
            for (var i = 0; i < 100; i++) o = state.Step(Dt, true, 0.5f);

            Assert.That(o.viewerX, Is.EqualTo(0.5f).Within(0.001f));
            Assert.That(o.viewerY, Is.EqualTo(0f));
        }

        [Test]
        public void Wake_StartsAtTargetOnEntry_SoThereIsNoTailYet()
        {
            var state = NewState();
            Run(state, 1f, false);

            var o = state.Step(Dt, true, 0.8f, -0.4f);
            Assert.That(o.wakeX, Is.EqualTo(0.8f));
            Assert.That(o.wakeY, Is.EqualTo(-0.4f));
        }

        [Test]
        public void Wake_TrailsBehindTheViewer_AndTakesLongerToArrive()
        {
            var state = NewState();
            state.Step(Dt, true, 0.8f, 0.6f);

            // The target jumps to the other corner. The viewer chases it, the wake chases more slowly, so the wake always stays
            // on the side the viewer came from and the tail between them is never negative.
            var o = default(NoticeOutput);
            for (var i = 0; i < 400; i++) // 8 s
            {
                o = state.Step(Dt, true, -0.8f, -0.6f);
                Assert.That(o.wakeX, Is.GreaterThanOrEqualTo(o.viewerX), $"x step {i}");
                Assert.That(o.wakeY, Is.GreaterThanOrEqualTo(o.viewerY), $"y step {i}");
                if (i == 14) // 0.3 s: the viewer is already well on its way, the wake has barely left (2.5 s time constant)
                {
                    Assert.That(o.wakeX, Is.InRange(0.55f, 0.7f));
                    Assert.That(o.wakeY, Is.InRange(0.4f, 0.55f));
                }
            }

            Assert.That(o.wakeX, Is.GreaterThan(o.viewerX + 0.05f), "still catching up after 8 s");
            Assert.That(Run(state, 15f, true, -0.8f, -0.6f).wakeX, Is.EqualTo(-0.8f).Within(0.01f), "and then it arrives");
            Assert.That(Run(state, 15f, true, -0.8f, -0.6f).wakeY, Is.EqualTo(-0.6f).Within(0.01f));
        }

        [TestCase(0.1f)] // quicker than the viewer's own lag
        [TestCase(0f)]   // unset, as in a scene saved before the setting existed
        public void Wake_NeverCatchesUpFasterThanTheViewer_WhateverTheWakeLag(float wakeLag)
        {
            var cfg = Cfg;
            cfg.wakeLag = wakeLag;
            var state = new NoticeState(cfg);
            state.Step(Dt, true, 0.8f, 0f);

            for (var i = 0; i < 400; i++)
            {
                var o = state.Step(Dt, true, -0.8f, 0f);
                Assert.That(o.wakeX, Is.GreaterThanOrEqualTo(o.viewerX), $"step {i}");
            }
        }

        [Test]
        public void Wake_HoldsAfterLeaving_AndSnapsAgainOnReentry()
        {
            var state = NewState();
            Run(state, 1f, true, 0.5f, 0.2f);
            var last = Run(state, 1f, true, -0.5f, -0.2f);

            var gone = Run(state, 2f, false, 1f, 1f);
            Assert.That(gone.wakeX, Is.EqualTo(last.wakeX));
            Assert.That(gone.wakeY, Is.EqualTo(last.wakeY));

            var back = state.Step(Dt, true, -0.9f, 0.7f);
            Assert.That(back.wakeX, Is.EqualTo(-0.9f));
            Assert.That(back.wakeY, Is.EqualTo(0.7f));
        }

        [TestCase(3f, 1f)]
        [TestCase(-3f, -1f)]
        public void Wake_ClampedToUnitRange(float target, float expected)
        {
            var state = NewState();
            Assert.That(state.Step(Dt, true, target, target).wakeX, Is.EqualTo(expected), "on entry");

            state = NewState();
            state.Step(Dt, true, 0f, 0f);
            var o = Run(state, 20f, true, target, target);
            Assert.That(o.wakeX, Is.EqualTo(expected).Within(0.01f), "while following");
            Assert.That(o.wakeY, Is.EqualTo(expected).Within(0.01f));
        }

        [Test]
        public void ReturningDuringAfterglow_StayDoesNotJump_AndTheVisitStartsOver()
        {
            var state = NewState();
            Run(state, 20f, true);
            var prev = Run(state, 2f, false).stay; // 10 s afterglow: 0.8 left
            Assert.That(prev, Is.EqualTo(0.8f).Within(0.02f));

            var peakHush = 0f;
            var stayAfterOneSecond = 0f;
            for (var i = 0; i < 500; i++) // 10 s back in the room
            {
                var o = state.Step(Dt, true, 0f);
                // Fastest allowed move per step is Dt / rampTime = 0.005.
                Assert.That(System.Math.Abs(o.stay - prev), Is.LessThan(0.006f));
                prev = o.stay;
                if (i < 105) peakHush = System.Math.Max(peakHush, o.hush);
                if (i == 49) stayAfterOneSecond = o.stay;
            }

            Assert.That(stayAfterOneSecond, Is.EqualTo(0.55f).Within(0.02f), "falling toward 0 while dwell restarts");
            Assert.That(peakHush, Is.GreaterThan(0.99f), "hush counts again");
            Assert.That(prev, Is.EqualTo(1f).Within(0.001f), "10 s later it has risen back to full");
        }

        [Test]
        public void Quiet_NoOneThere_StaysZero_WindowsEmpty()
        {
            var o = Run(NewState(), 5f, false);

            Assert.That(o.quiet, Is.EqualTo(0f));
            Assert.That(o.quietFrom, Is.EqualTo(0f));
            Assert.That(o.quietUntil, Is.EqualTo(0f));
            Assert.That(o.quietFrom2, Is.EqualTo(0f));
            Assert.That(o.quietUntil2, Is.EqualTo(0f));
        }

        [Test]
        public void Quiet_RisesToOneOverQuietRise_NeverDown()
        {
            var state = NewState();
            var prev = 0f;
            var o = default(NoticeOutput);
            for (var i = 0; i < 250; i++) // 5 s, the default quietRise
            {
                o = state.Step(Dt, true, 0f);
                Assert.That(o.quiet, Is.GreaterThanOrEqualTo(prev));
                prev = o.quiet;
                if (i == 124) Assert.That(o.quiet, Is.EqualTo(0.5f).Within(0.02f));
            }

            Assert.That(o.quiet, Is.EqualTo(1f).Within(0.001f));
            Assert.That(Run(state, 5f, true).quiet, Is.EqualTo(1f), "stays capped");
        }

        [Test]
        public void QuietWindow_OpensOnEntry_AtTheClock_AndStaysOpenWhilePresent()
        {
            var state = NewState();
            Run(state, 3f, false);

            var o = state.Step(Dt, true, 0f);
            Assert.That(o.quietFrom, Is.EqualTo(o.clock));
            Assert.That(o.quietFrom, Is.GreaterThan(2.9f));
            Assert.That(o.quietUntil, Is.EqualTo(NoticeState.Forever));
            Assert.That(o.quietFrom2, Is.EqualTo(0f));
            Assert.That(o.quietUntil2, Is.EqualTo(0f));

            var from = o.quietFrom;
            for (var i = 0; i < 750; i++) // 15 s, still there
            {
                o = state.Step(Dt, true, 0f);
                Assert.That(o.quietUntil, Is.EqualTo(NoticeState.Forever));
                Assert.That(o.quietFrom, Is.EqualTo(from));
            }
        }

        [Test]
        public void QuietWindow_ClosesWhenTheAfterglowEnds_ThenNeverChanges()
        {
            var state = NewState();
            var entered = Run(state, 20f, true); // 10 s afterglow
            var prev = entered.quiet;
            var closedAt = -1f;
            for (var i = 0; i < 800; i++) // 16 s
            {
                var o = state.Step(Dt, false, 0f);
                Assert.That(o.quiet, Is.LessThanOrEqualTo(prev));
                prev = o.quiet;
                Assert.That(o.quietFrom, Is.EqualTo(entered.quietFrom));

                if (o.quiet > 0f)
                {
                    Assert.That(o.quietUntil, Is.EqualTo(NoticeState.Forever), "open through the afterglow");
                    continue;
                }

                if (closedAt < 0f)
                {
                    closedAt = o.clock;
                    Assert.That(o.quietUntil, Is.EqualTo(o.clock), "closed on the step quiet hit 0");
                }
                Assert.That(o.quietUntil, Is.EqualTo(closedAt));
            }

            Assert.That(closedAt, Is.GreaterThan(0f), "it did close");
            Assert.That(closedAt, Is.LessThan(NoticeState.Forever));
            Assert.That(closedAt - entered.clock, Is.EqualTo(10f).Within(0.1f));
        }

        [Test]
        public void QuietWindow_SecondVisitOpensNewWindow_FirstOneMovesToPrevious()
        {
            var state = NewState();
            Run(state, 3f, false);
            Run(state, 5f, true); // 2.5 s afterglow
            var first = Run(state, 20f, false);
            Assert.That(first.quiet, Is.EqualTo(0f));
            Assert.That(first.quietUntil, Is.LessThan(NoticeState.Forever));

            Run(state, 5f, false);
            var o = state.Step(Dt, true, 0f);

            Assert.That(o.quietFrom, Is.EqualTo(o.clock));
            Assert.That(o.quietFrom, Is.GreaterThan(first.quietUntil));
            Assert.That(o.quietUntil, Is.EqualTo(NoticeState.Forever));
            Assert.That(o.quietFrom2, Is.EqualTo(first.quietFrom));
            Assert.That(o.quietUntil2, Is.EqualTo(first.quietUntil));
        }

        [Test]
        public void QuietWindow_ReturningDuringAfterglow_ContinuesTheSameWindow()
        {
            var state = NewState();
            Run(state, 3f, false);
            var first = Run(state, 20f, true);
            Assert.That(Run(state, 2f, false).quiet, Is.EqualTo(0.8f).Within(0.02f)); // 10 s afterglow, 8 s left

            for (var i = 0; i < 250; i++) // 5 s back in the room
            {
                var o = state.Step(Dt, true, 0f);
                Assert.That(o.quietFrom, Is.EqualTo(first.quietFrom));
                Assert.That(o.quietUntil, Is.EqualTo(NoticeState.Forever));
                Assert.That(o.quietFrom2, Is.EqualTo(first.quietFrom2));
                Assert.That(o.quietUntil2, Is.EqualTo(first.quietUntil2));
            }

            Assert.That(Run(state, 3f, true).quiet, Is.EqualTo(1f).Within(0.001f), "turned back up");
        }

        [Test]
        public void QuietWindow_PassingBy_StillMakesOne_AndQuietReturnsToZero()
        {
            var state = NewState();
            Run(state, 3f, false);

            var peak = Run(state, 1f, true).quiet; // 1 s of the 5 s quietRise
            Assert.That(peak, Is.EqualTo(0.2f).Within(0.01f));

            var o = Run(state, 5f, false); // afterglow is 1 s at the minimum
            Assert.That(o.quiet, Is.EqualTo(0f));
            Assert.That(o.quietFrom, Is.GreaterThan(2.9f));
            Assert.That(o.quietUntil, Is.LessThan(NoticeState.Forever));
            Assert.That(o.quietUntil, Is.GreaterThan(o.quietFrom));
        }

        [Test]
        public void NonPositiveDt_OpensNoQuietWindow()
        {
            var state = NewState();
            foreach (var o in new[] { state.Step(0f, true, 0f), state.Step(float.NaN, true, 0f) })
            {
                Assert.That(o.quiet, Is.EqualTo(0f));
                Assert.That(o.quietFrom, Is.EqualTo(0f));
                Assert.That(o.quietUntil, Is.EqualTo(0f));
            }
        }

        [Test]
        public void NonPositiveDt_AdvancesNothing()
        {
            var state = NewState();
            var a = Run(state, 3f, true, 0.5f);
            var b = state.Step(0f, true, 0.5f);
            var c = state.Step(-1f, false, 0f);

            foreach (var o in new[] { b, c })
            {
                Assert.That(o.clock, Is.EqualTo(a.clock));
                Assert.That(o.stay, Is.EqualTo(a.stay));
                Assert.That(o.hush, Is.EqualTo(a.hush));
                Assert.That(o.viewerX, Is.EqualTo(a.viewerX));
                Assert.That(o.wakeX, Is.EqualTo(a.wakeX));
                Assert.That(o.present, Is.True, "a skipped step doesn't register the exit");
            }
        }

        [Test]
        public void Aware_StaysZeroThroughTheDelay_ThenRisesSmoothlyToOneOverAwareRise()
        {
            var state = NewState();
            Assert.That(Run(state, 0.4f, true).aware, Is.EqualTo(0f));

            var maxRise = MaxStep(Cfg.awareRise);
            var prev = 0f;
            var steps = (int)((Cfg.noticeDelay - 0.4f + Cfg.awareRise) / Dt + 0.5f) + 2;
            for (var i = 0; i < steps; i++)
            {
                var aware = state.Step(Dt, true, 0f).aware;
                Assert.That(aware - prev, Is.InRange(0f, maxRise), $"step {i}");
                prev = aware;
            }

            Assert.That(prev, Is.EqualTo(1f));
        }

        [Test]
        public void Aware_DrainsOverTheAfterglow_AndReenteringCarriesOnFromWhereItIs()
        {
            var state = NewState();
            Run(state, 6f, true); // afterglow = 6 * 0.5 = 3 s
            var half = Run(state, 1.5f, false).aware;
            Assert.That(half, Is.EqualTo(0.5f).Within(0.02f));

            Assert.That(state.Step(Dt, true, 0f).aware, Is.EqualTo(half), "holds through the new delay, no jump");
            Assert.That(Run(state, 1.6f, true).aware, Is.EqualTo(1f));
        }
    }
}
