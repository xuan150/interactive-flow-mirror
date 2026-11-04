using UnityEngine;
using UnityEngine.VFX;

namespace FlowMirror.Idle
{
    // Keeps the mirror's exposed properties in step with the world's, so only the world's VisualEffect needs tuning in the Inspector.
    [ExecuteAlways]
    [RequireComponent(typeof(VisualEffect))]
    public class IdleMirror : MonoBehaviour
    {
        [SerializeField] VisualEffect world;

        static readonly string[] Names =
        {
            "Dot Opacity", "Dot Size", "Brightness", "Distance Haze", "Far Layer Opacity", "Horizon Height", "Horizon Waviness", "Mirror Strength", "Horizon Glow", "Color Variety", "Color Warmth", "Split Distance", "Gather Strength", "Extend Reach", "Receiver Glow", "Transfer Amount", "Transfer Interval", "Transfer Duration", "Depth Drift Period", "Width Follow", "Run Seed",
            "Notice Width Stay", "Notice Width Long", "Notice Height Stay", "Notice Height Long", "Notice Rim Softness", "Notice Rim Burn Guard", "Notice Edge Ragged", "Notice Width Wobble", "Notice Tilt",
            "Notice Orbit Share Stay", "Notice Orbit Share Long", "Notice Orbit Reach Stay", "Notice Orbit Reach Long", "Notice Orbit Inside", "Notice Pulse Sweep", "Notice Pulse Stop",
            "Notice Core Keep", "Notice Deflect",
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
