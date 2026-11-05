using System;
using UnityEngine;
using UnityEngine.VFX;

namespace FlowMirror
{
    // Which parts of the world's reaction are on. None = the plain idle, exactly as before. The values are a bit mask the
    // idle HLSL reads (Notice_PARTS_* in Notice_Common.hlsl).
    [Flags]
    public enum NoticeParts { None = 0, Clear = 1, Pulse = 2, Focus = 4, Flow = 8 }

    // Test only: which of Flow's two pushes are on, to judge each alone against the same visit. The values are the HLSL's test bits
    // (Notice_FLOW_NO_AVOID 16, Notice_FLOW_NO_SLIDE 32, Notice_FLOW_SHOW_OFFSET 64), added to the mask only while Flow is on.
    public enum FlowTerms { Both = 0, AvoidOnly = 32, SlideOnly = 16, ShowOffset = 64 }

    // Test only: hold the idle still, so the reaction to the viewer can be judged on its own and Idle, Clear and Flow line up frame by
    // frame. Same Clock runs the plain idle on the world clock too (HLSL bit Notice_HOLD_CLOCK); Shape holds the clock, so the ribbons
    // keep the shape they had when it was switched on, and the dots stream on their own age (Notice_HOLD_STREAM); All holds everything.
    public enum IdleHold { Off, SameClock, Shape, All }

    // Notice layer glue: reads the viewers from the PersonTracker, runs NoticeState, and hands the result to the idle VFX
    // as exposed floats every frame. The VFX reads them as the world clock and the strength of each stage.
    public class NoticeSensor : MonoBehaviour
    {
        [SerializeField] PersonTracker tracker;
        [Tooltip("VFX objects that receive the notice values: the veil, its reflection and the fly-by.")]
        [SerializeField] VisualEffect[] targets;
        [Tooltip("Camera that turns a viewer's position into a screen position. Empty = Main Camera.")]
        [SerializeField] Camera cam;
        [Tooltip("Clear: dots leave a patch around the viewer. Pulse: a ring comes in and brakes at its rim. Focus: crisp rim, soft far away. Flow: the dots bend around the viewer and drift home once they leave (instead of the other three). None = the plain idle.")]
        [SerializeField] NoticeParts parts = NoticeParts.Clear | NoticeParts.Pulse;
        [Tooltip("Test only, with Flow on. Both = the real look; Avoid Only = the dots are only moved off the viewer's edge; Slide Only = only slid along it; Show Offset = Both, with the dots tinted red by how far they have been moved. The pull back home is always on.")]
        [SerializeField] FlowTerms flowTerms = FlowTerms.Both;
        [Tooltip("Test only. Same Clock: the plain idle (Parts None) runs on the world clock too, hush included, so Idle, Clear and Flow line up frame by frame. Shape: the ribbons hold the shape they had when this was switched on, the dots keep streaming along them. All: the whole idle stands still, only the reaction to the viewer moves. Switch it before the viewer comes in: switching jumps the picture.")]
        [SerializeField] IdleHold idleHold;
        [Tooltip("Draw where the world thinks the viewer is (a cross) and which stage it is in, on the Game view.")]
        [SerializeField] bool showDebug = true;
        [SerializeField] NoticeSettings settings = NoticeSettings.Default;

        NoticeState state;
        NoticeOutput last;
        // The world clock at the moment Idle Hold went to Shape or All.
        float heldClock;
        bool held;

        void OnEnable()
        {
            state = new NoticeState(settings);
            if (!cam) cam = Camera.main;
        }

        void LateUpdate()
        {
            state.Settings = settings;
            var persons = tracker.Persons;
            var present = persons.Count > 0;
            // One viewer for now: the first one in. Screen position runs -1..1 whatever the camera.
            var x = 0f;
            var y = 0f;
            if (present)
            {
                var p = persons[0].position;
                var view = cam.WorldToViewportPoint(new Vector3(p.x, p.y, 0f));
                x = view.x * 2f - 1f;
                y = view.y * 2f - 1f;
            }
            var o = last = state.Step(Time.deltaTime, present, x, y);
            var mode = (int)parts | ((parts & NoticeParts.Flow) != 0 ? (int)flowTerms : 0);
            if (idleHold != IdleHold.Off) mode |= 128;
            if (idleHold == IdleHold.Shape) mode |= 256;
            var hold = idleHold >= IdleHold.Shape;
            if (hold && !held) heldClock = o.clock;
            held = hold;

            foreach (var vfx in targets)
            {
                if (!vfx) continue;
                Set(vfx, "Notice Mode", mode);
                Set(vfx, "Notice Clock", hold ? heldClock : o.clock);
                Set(vfx, "Notice Stay", o.stay);
                Set(vfx, "Notice Long Stay", o.longStay);
                Set(vfx, "Notice Viewer X", o.viewerX);
                Set(vfx, "Notice Viewer Y", o.viewerY);
                Set(vfx, "Notice Wake X", o.wakeX);
                Set(vfx, "Notice Wake Y", o.wakeY);
                Set(vfx, "Notice Aware", o.aware);
                Set(vfx, "Notice Quiet", o.quiet);
                Set(vfx, "Notice Quiet From", o.quietFrom);
                Set(vfx, "Notice Quiet Until", o.quietUntil);
                Set(vfx, "Notice Quiet From 2", o.quietFrom2);
                Set(vfx, "Notice Quiet Until 2", o.quietUntil2);
            }
        }

        static void Set(VisualEffect vfx, string name, float value)
        {
            if (vfx.HasFloat(name)) vfx.SetFloat(name, value);
        }

        // A plus sign at a screen position given as -1..1, arms `half` pixels long.
        static void DrawCross(float x, float y, float half, float alpha)
        {
            var px = (x * 0.5f + 0.5f) * Screen.width;
            var py = (0.5f - y * 0.5f) * Screen.height;
            GUI.color = new Color(1f, 0.9f, 0.2f, alpha);
            GUI.DrawTexture(new Rect(px - half, py - 1f, half * 2f, 2f), Texture2D.whiteTexture);
            GUI.DrawTexture(new Rect(px - 1f, py - half, 2f, half * 2f), Texture2D.whiteTexture);
        }

        void OnGUI()
        {
            if (!showDebug) return;
            if (last.present)
            {
                var old = GUI.color;
                DrawCross(last.viewerX, last.viewerY, 12f, 0.8f);
                // The wake: a smaller dim cross where the world thinks the viewer just was.
                DrawCross(last.wakeX, last.wakeY, 6f, 0.35f);
                GUI.color = old;
            }
            GUI.Label(new Rect(10f, 10f, 800f, 24f),
                $"notice {parts}{((parts & NoticeParts.Flow) != 0 && flowTerms != FlowTerms.Both ? $" ({flowTerms})" : "")}{(idleHold != IdleHold.Off ? $"   hold {idleHold}" : "")}   {(last.present ? "viewer in" : "no viewer")}   aware {last.aware:0.00}   hush {last.hush:0.00}   stay {last.stay:0.00}   long {last.longStay:0.00}   x {last.viewerX:0.00}  y {last.viewerY:0.00}");
        }
    }
}
