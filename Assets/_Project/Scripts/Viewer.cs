using UnityEngine;

namespace FlowMirror
{
    // Input layer: one choreographed viewer, a child of the PersonTracker. Enabling the GameObject (Timeline Activation
    // track) brings the viewer in, moving its transform (Animation track) moves them, disabling takes them out.
    public class Viewer : MonoBehaviour
    {
        PersonTracker tracker;
        uint? id;

        void OnEnable()
        {
            tracker = GetComponentInParent<PersonTracker>();
            if (!tracker.IsFull) id = tracker.Add(transform.position);
        }

        void Update()
        {
            if (id.HasValue) tracker.Move(id.Value, transform.position);
        }

        void OnDisable()
        {
            if (id.HasValue && tracker) tracker.Remove(id.Value);
            id = null;
        }

        // Edit mode shows no figures: draw the body (SilhouetteMask Height 6, the 2-wide capsule) to stage the choreography.
        void OnDrawGizmos() => Gizmos.DrawWireCube(transform.position, new Vector3(2f, 6f, 0f));
    }
}
