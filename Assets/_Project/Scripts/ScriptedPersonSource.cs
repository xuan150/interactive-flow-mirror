using UnityEngine;

namespace FlowMirror
{
    // Input layer, for A/B recordings: one fake viewer who makes the same visit every time, so two runs (Clear against Flow, or
    // Flow's test terms) can be compared side by side. Off by default; switch it on instead of using the mouse, together with
    // IdleMirror's Fixed Seed. The visit (seconds after Play, or after this is switched on): nobody until enterAt, then standing at
    // `first`, walking to `second` from walkAt over walkTime, standing there, gone at leaveAt. docs/notice-flow-check.js uses the
    // same visit.
    [RequireComponent(typeof(PersonTracker))]
    public class ScriptedPersonSource : MonoBehaviour
    {
        [Tooltip("Camera that turns the screen positions below into the viewers' plane. Empty = Main Camera.")]
        [SerializeField] Camera cam;
        [Tooltip("Where the viewer stands first, as a screen position (0 - 1 each way).")]
        [SerializeField] Vector2 first = new(0.425f, 0.475f);
        [Tooltip("Where the viewer walks to, as a screen position (0 - 1 each way).")]
        [SerializeField] Vector2 second = new(0.56f, 0.475f);
        [SerializeField] float enterAt = 5f;
        [SerializeField] float walkAt = 17f;
        [SerializeField] float walkTime = 3f;
        [SerializeField] float leaveAt = 24f;

        PersonTracker tracker;
        uint? id;
        float t;

        void Awake()
        {
            tracker = GetComponent<PersonTracker>();
            if (!cam) cam = Camera.main;
        }

        void OnEnable() => t = 0f;

        void OnDisable()
        {
            if (id.HasValue) tracker.Remove(id.Value);
            id = null;
        }

        void Update()
        {
            t += Time.deltaTime;
            var there = t >= enterAt && t < leaveAt;
            if (there && !id.HasValue && !tracker.IsFull) id = tracker.Add(ToWorld(At(t)));
            else if (!there && id.HasValue)
            {
                tracker.Remove(id.Value);
                id = null;
            }
            if (id.HasValue) tracker.Move(id.Value, ToWorld(At(t)));
        }

        Vector2 At(float time) => Vector2.Lerp(first, second, Mathf.Clamp01((time - walkAt) / Mathf.Max(walkTime, 1e-4f)));

        // The distance puts the point on the plane the viewers stand on (z = 0), as MousePersonSource does.
        Vector2 ToWorld(Vector2 screen) => cam.ViewportToWorldPoint(new Vector3(screen.x, screen.y, -cam.transform.position.z));
    }
}
