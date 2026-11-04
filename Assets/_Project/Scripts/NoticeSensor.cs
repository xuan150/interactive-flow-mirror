using System;
using UnityEngine;
using UnityEngine.VFX;

namespace FlowMirror
{
    // Which parts of the world's reaction are on. None = the plain idle, exactly as before. The values are a bit mask the
    // idle HLSL reads (Notice_PARTS_* in Notice_Common.hlsl).
    [Flags]
    public enum NoticeParts { None = 0, Clear = 1, Pulse = 2, Focus = 4 }

    // Notice layer glue: reads the viewers from the PersonTracker, runs NoticeState, and hands the result to the idle VFX
    // as exposed floats every frame. The VFX reads them as the world clock and the strength of each stage.
    public class NoticeSensor : MonoBehaviour
    {
        [SerializeField] PersonTracker tracker;
        [Tooltip("VFX objects that receive the notice values: the veil, its reflection and the fly-by.")]
        [SerializeField] VisualEffect[] targets;
        [Tooltip("Camera that turns a viewer's position into a screen position. Empty = Main Camera.")]
        [SerializeField] Camera cam;
        [Tooltip("Clear: dots leave a patch around the viewer. Pulse: a ring comes in and brakes at its rim. Focus: crisp rim, soft far away. None = the plain idle.")]
        [SerializeField] NoticeParts parts = NoticeParts.Clear | NoticeParts.Pulse;
        [Tooltip("Draw where the world thinks the viewer is (a cross) and which stage it is in, on the Game view.")]
        [SerializeField] bool showDebug = true;
        [SerializeField] NoticeSettings settings = NoticeSettings.Default;

        NoticeState state;
        NoticeOutput last;

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

            foreach (var vfx in targets)
            {
                if (!vfx) continue;
                Set(vfx, "Notice Mode", (float)(int)parts);
                Set(vfx, "Notice Clock", o.clock);
                Set(vfx, "Notice Stay", o.stay);
                Set(vfx, "Notice Long Stay", o.longStay);
                Set(vfx, "Notice Viewer X", o.viewerX);
                Set(vfx, "Notice Viewer Y", o.viewerY);
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

        void OnGUI()
        {
            if (!showDebug) return;
            if (last.present)
            {
                var px = (last.viewerX * 0.5f + 0.5f) * Screen.width;
                var py = (0.5f - last.viewerY * 0.5f) * Screen.height;
                var old = GUI.color;
                GUI.color = new Color(1f, 0.9f, 0.2f, 0.8f);
                GUI.DrawTexture(new Rect(px - 12f, py - 1f, 24f, 2f), Texture2D.whiteTexture);
                GUI.DrawTexture(new Rect(px - 1f, py - 12f, 2f, 24f), Texture2D.whiteTexture);
                GUI.color = old;
            }
            GUI.Label(new Rect(10f, 10f, 640f, 24f),
                $"notice {parts}   {(last.present ? "viewer in" : "no viewer")}   hush {last.hush:0.00}   stay {last.stay:0.00}   long {last.longStay:0.00}   x {last.viewerX:0.00}  y {last.viewerY:0.00}");
        }
    }
}
