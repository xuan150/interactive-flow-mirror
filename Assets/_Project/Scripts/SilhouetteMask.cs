using UnityEngine;
using UnityEngine.VFX;

namespace FlowMirror
{
    // Input layer: the ID mask of ADR 0001. Silhouette.compute stamps the silhouette picture at every fake person,
    // then blurs it into a soft body the lines can make way around.
    // Mask texel = (hard index + 1, hard coverage, soft index, soft coverage).
    [RequireComponent(typeof(PersonTracker))]
    public class SilhouetteMask : MonoBehaviour
    {
        // Same density as RippleField: 1/4 of the 1920x960 Game view.
        static readonly Vector2Int Resolution = new(480, 240);

        static readonly int SilhouetteMaskId = Shader.PropertyToID("SilhouetteMask");
        static readonly int MaskId = Shader.PropertyToID("Mask");
        static readonly int HardId = Shader.PropertyToID("Hard");
        static readonly int HardInId = Shader.PropertyToID("HardIn");
        static readonly int BlurredId = Shader.PropertyToID("Blurred");
        static readonly int BlurredInId = Shader.PropertyToID("BlurredIn");
        static readonly int SilhouetteId = Shader.PropertyToID("Silhouette");
        static readonly int PositionsId = Shader.PropertyToID("Positions");
        static readonly int CountId = Shader.PropertyToID("Count");
        static readonly int SizeId = Shader.PropertyToID("Size");
        static readonly int AreaId = Shader.PropertyToID("Area");
        static readonly int BodySizeId = Shader.PropertyToID("BodySize");
        static readonly int SoftRadiusId = Shader.PropertyToID("SoftRadius");

        [Tooltip("Silhouette.compute.")]
        [SerializeField] ComputeShader shader;
        [Tooltip("Person shape: a PNG with a transparent background. Pixels with alpha above half count as body.")]
        [SerializeField] Texture2D silhouette;
        [Tooltip("VFX objects that receive the mask as SilhouetteMask every frame.")]
        [SerializeField] VisualEffect[] targets;
        [Tooltip("Body height in world units (the view is 10 tall). The width follows the picture's aspect ratio.")]
        [SerializeField] float height = 6f;
        [Tooltip("How far from the body the lines start to make way and glow, in world units.")]
        [SerializeField] float softness = 1f;
        [Tooltip("Shows the mask in the top-left corner of the Game view: body in yellow, soft body as a faint halo.")]
        [SerializeField] bool showDebug = true;

        PersonTracker tracker;
        RenderTexture hard;
        RenderTexture blurred;
        RenderTexture mask;
        int stampKernel;
        int blurXKernel;
        int blurYKernel;
        readonly Vector4[] positions = new Vector4[PersonTracker.MaxPersons];

        void Awake() => tracker = GetComponent<PersonTracker>();

        void OnEnable()
        {
            stampKernel = shader.FindKernel("Stamp");
            blurXKernel = shader.FindKernel("BlurX");
            blurYKernel = shader.FindKernel("BlurY");
            hard = CreateTexture(RenderTextureFormat.RGHalf);
            blurred = CreateTexture(RenderTextureFormat.RGHalf);
            mask = CreateTexture(RenderTextureFormat.ARGBHalf);
        }

        void OnDisable()
        {
            hard.Release();
            blurred.Release();
            mask.Release();
        }

        static RenderTexture CreateTexture(RenderTextureFormat format)
        {
            var rt = new RenderTexture(Resolution.x, Resolution.y, 0, format)
            {
                enableRandomWrite = true,
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp,
            };
            rt.Create();
            return rt;
        }

        void Update()
        {
            var persons = tracker.Persons;
            for (var i = 0; i < persons.Count; i++) positions[i] = persons[i].position;

            shader.SetVectorArray(PositionsId, positions);
            shader.SetInt(CountId, persons.Count);
            shader.SetInts(SizeId, Resolution.x, Resolution.y);
            shader.SetVector(AreaId, PersonTracker.Area);
            shader.SetVector(BodySizeId, new Vector2(height * silhouette.width / silhouette.height, height));
            shader.SetFloat(SoftRadiusId, Mathf.Max(softness, 0f) / PersonTracker.Area.x * Resolution.x);

            var groupsX = Mathf.CeilToInt(Resolution.x / 8f);
            var groupsY = Mathf.CeilToInt(Resolution.y / 8f);
            shader.SetTexture(stampKernel, SilhouetteId, silhouette);
            shader.SetTexture(stampKernel, HardId, hard);
            shader.Dispatch(stampKernel, groupsX, groupsY, 1);
            shader.SetTexture(blurXKernel, HardInId, hard);
            shader.SetTexture(blurXKernel, BlurredId, blurred);
            shader.Dispatch(blurXKernel, groupsX, groupsY, 1);
            shader.SetTexture(blurYKernel, HardInId, hard);
            shader.SetTexture(blurYKernel, BlurredInId, blurred);
            shader.SetTexture(blurYKernel, MaskId, mask);
            shader.Dispatch(blurYKernel, groupsX, groupsY, 1);

            foreach (var vfx in targets)
                if (vfx && vfx.HasTexture(SilhouetteMaskId)) vfx.SetTexture(SilhouetteMaskId, mask);
        }

        void OnGUI()
        {
            if (showDebug && mask) GUI.DrawTexture(new Rect(10, 10, 360, 180), mask);
        }
    }
}
