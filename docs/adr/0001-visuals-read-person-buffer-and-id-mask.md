# Visuals read only a person buffer and an ID mask

The visual layer (fields and VFX Graph) never knows where people come from. It reads exactly two inputs: a `GraphicsBuffer` of people (`id, position, velocity, colorA, colorB`, fixed max count) and one ID-mask RenderTexture where each pixel holds `person index + 1` (0 = nobody). Input sources (mouse fake people now, webcam segmentation later) must produce both, with mirroring done on the input side. We chose this so that swapping fake people for real people later touches only the input layer; it also means fake people must stamp a silhouette texture into the mask, which looks like overkill for mouse input but keeps the contract identical.

## Considered Options

- **Positions only**: simplest, but cannot draw a silhouette, which is the core of the piece.
- **One mask texture per person**: unbounded texture count and awkward to sample in VFX Graph.
- **Single binary mask**: cannot tell people apart, so color exchange and per-person vortices break when people overlap.
