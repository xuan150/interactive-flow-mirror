using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.VFX;

namespace FlowMirror
{
    // Person-state layer: owns the person list, derives velocity, uploads to the GPU every frame.
    public class PersonTracker : MonoBehaviour
    {
        // Fixed: the GPU buffer is sized once in OnEnable, and Vortex.hlsl loops over at most 8.
        public const int MaxPersons = 8;
        // World area the fields and masks cover, centered on the origin = the camera view (Size 5, 2:1).
        // Vortex.hlsl and Silhouette.hlsl hardcode the same 20 x 10; change them together.
        public static readonly Vector2 Area = new(20f, 10f);

        static readonly int PersonsId = Shader.PropertyToID("Persons");
        static readonly int PersonCountId = Shader.PropertyToID("PersonCount");

        static readonly Color[] Palette =
        {
            new(0.35f, 0.85f, 1f), new(1f, 0.55f, 0.35f), new(0.7f, 0.5f, 1f), new(0.45f, 1f, 0.6f),
        };

        [Tooltip("VFX objects that receive the Persons buffer and PersonCount every frame.")]
        [SerializeField] VisualEffect[] targets;
        [Tooltip("Higher = velocity follows movement faster, lower = smoother.")]
        [SerializeField] float velocitySmoothing = 10f;

        readonly List<Person> persons = new();
        readonly List<Vector2> previousPositions = new();
        GraphicsBuffer buffer;
        uint nextId = 1;

        public IReadOnlyList<Person> Persons => persons;
        public bool IsFull => persons.Count >= MaxPersons;

        void OnEnable()
        {
            buffer = new GraphicsBuffer(GraphicsBuffer.Target.Structured, MaxPersons, Marshal.SizeOf<Person>());
        }

        void OnDisable()
        {
            buffer?.Release();
            buffer = null;
        }

        public uint Add(Vector2 position)
        {
            var id = nextId++;
            Color color = Palette[(int)(id % Palette.Length)];
            persons.Add(new Person { id = id, position = position, colorA = color, colorB = color });
            previousPositions.Add(position);
            return id;
        }

        public void Move(uint id, Vector2 position)
        {
            var i = IndexOf(id);
            if (i < 0) return;
            var p = persons[i];
            p.position = position;
            persons[i] = p;
        }

        public void Remove(uint id)
        {
            var i = IndexOf(id);
            if (i < 0) return;
            persons.RemoveAt(i);
            previousPositions.RemoveAt(i);
        }

        int IndexOf(uint id) => persons.FindIndex(p => p.id == id);

        void LateUpdate()
        {
            var dt = Time.deltaTime;
            if (dt > 0f)
            {
                var blend = 1f - Mathf.Exp(-velocitySmoothing * dt);
                for (var i = 0; i < persons.Count; i++)
                {
                    var p = persons[i];
                    var raw = (p.position - previousPositions[i]) / dt;
                    p.velocity = Vector2.Lerp(p.velocity, raw, blend);
                    persons[i] = p;
                    previousPositions[i] = p.position;
                }
            }

            if (persons.Count > 0) buffer.SetData(persons);
            foreach (var vfx in targets)
            {
                if (!vfx || !vfx.HasGraphicsBuffer(PersonsId) || !vfx.HasInt(PersonCountId)) continue;
                vfx.SetGraphicsBuffer(PersonsId, buffer);
                vfx.SetInt(PersonCountId, persons.Count);
            }
        }
    }
}
