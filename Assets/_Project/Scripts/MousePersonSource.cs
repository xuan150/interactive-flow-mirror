using UnityEngine;
using UnityEngine.InputSystem;

namespace FlowMirror
{
    // Input layer: fake people driven by the mouse. Left click empty space to add (and start dragging),
    // left drag to move, right click to remove. Clicks only act on the person under the cursor.
    [RequireComponent(typeof(PersonTracker))]
    public class MousePersonSource : MonoBehaviour
    {
        [SerializeField] Camera cam;
        [SerializeField] float pickRadius = 0.6f;

        PersonTracker tracker;
        uint? dragging;
        uint? hovered;

        void Awake()
        {
            tracker = GetComponent<PersonTracker>();
            if (!cam) cam = Camera.main;
        }

        void Update()
        {
            var mouse = Mouse.current;
            if (mouse == null) return;

            Vector2 point = cam.ScreenToWorldPoint(mouse.position.ReadValue());
            hovered = Pick(point);

            if (mouse.leftButton.wasPressedThisFrame)
            {
                if (hovered.HasValue) dragging = hovered;
                else if (!tracker.IsFull) dragging = tracker.Add(point);
            }
            if (mouse.leftButton.wasReleasedThisFrame) dragging = null;
            if (dragging.HasValue) tracker.Move(dragging.Value, point);

            if (mouse.rightButton.wasPressedThisFrame && hovered.HasValue)
            {
                tracker.Remove(hovered.Value);
                if (dragging == hovered) dragging = null;
            }
        }

        // Nearest person within pickRadius, so overlapping people resolve to the one you point at.
        uint? Pick(Vector2 point)
        {
            uint? best = null;
            var bestDistance = pickRadius;
            foreach (var p in tracker.Persons)
            {
                var d = Vector2.Distance(p.position, point);
                if (d > bestDistance) continue;
                bestDistance = d;
                best = p.id;
            }
            return best;
        }

        // ponytail: Gizmos marker only shows with the Game view Gizmos toggle on; replaced by the silhouette in Sketch 05.
        void OnDrawGizmos()
        {
            if (!tracker) return;
            foreach (var p in tracker.Persons)
            {
                Gizmos.color = p.id == hovered ? Color.white : new Color(1f, 1f, 1f, 0.35f);
                Gizmos.DrawWireSphere(p.position, pickRadius);
            }
        }
    }
}
