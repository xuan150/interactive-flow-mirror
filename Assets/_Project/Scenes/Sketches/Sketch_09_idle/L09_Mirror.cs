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
            "Dot Opacity", "Dot Size", "Brightness", "Distance Haze", "Far Layer Opacity", "Horizon Height", "Horizon Waviness", "Mirror Strength", "Horizon Glow", "Color Variety", "Color Warmth", "Split Distance", "Gather Strength", "Extend Reach", "Receiver Glow", "Transfer Amount", "Transfer Interval", "Transfer Duration", "Depth Drift Period", "Width Follow", "Run Seed",
        };

        VisualEffect mirror;

        // A different order of events at every start: one random number, set on the world; the copies below follow it.
        void Awake()
        {
            if (Application.isPlaying && world != null && world.HasFloat("Run Seed"))
                world.SetFloat("Run Seed", Random.Range(1, 1000000));
        }

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
