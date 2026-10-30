using UnityEngine;
using UnityEngine.VFX;

namespace FlowMirror.Lookdev09
{
    // Sketch 09 (look-dev, throwaway): keeps the mirror's exposed properties in step with the world's, so only the world's
    // VisualEffect needs tuning in the Inspector.
    [ExecuteAlways]
    [RequireComponent(typeof(VisualEffect))]
    public class L09Mirror : MonoBehaviour
    {
        [SerializeField] VisualEffect world;

        static readonly string[] Names =
        {
            "Alpha", "Size", "Brightness", "Distance Fade", "Far Alpha", "Horizon Height", "Horizon Wave", "Reflection",
            "Horizon Line", "Color Spread", "Color Shift", "Split Gap", "Gather Pull", "Extend Length", "Event Glow",
        };

        VisualEffect mirror;

        void LateUpdate()
        {
            if (world == null) return;
            if (mirror == null) mirror = GetComponent<VisualEffect>();
            foreach (string n in Names)
                if (world.HasFloat(n) && mirror.HasFloat(n))
                    mirror.SetFloat(n, world.GetFloat(n));
        }
    }
}
