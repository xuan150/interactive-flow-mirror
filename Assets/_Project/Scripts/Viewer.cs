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

        // Nothing is drawn for a viewer, so mark where they stand (a 2 x 6 box) to stage the choreography in edit mode.
        void OnDrawGizmos() => Gizmos.DrawWireCube(transform.position, new Vector3(2f, 6f, 0f));
    }
}
