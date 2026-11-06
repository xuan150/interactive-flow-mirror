# The nameless world reads presences only

Status: proposed, side by side with [ADR 0001](0001-visuals-read-person-buffer-and-id-mask.md). The two describe two directions that are both kept so they can be compared before one is chosen; neither supersedes the other yet.

The nameless world (無名之物, look-dev approved 2026-11-06, prototype in [docs/lookdev/nameless.html](../lookdev/nameless.html)) never draws a viewer. Its visual layer reads only a presence per viewer: a line of sight (origin and direction), the point where that line meets the plane through the body, a strength that eases in and out, and the seconds they have stayed. The body parts around the line of sight and a loose band of particles streams after the point, more of it the longer they stay. No ID mask and no silhouette exist on this side. The creature and the shell are one stateful particle set in one GPU simulation: each frame a target pulls the particles in (the creature's metaball surface, the shell's deformed sphere, or a blend while one kind turns into the other), and a pure C# conductor decides, irregularly, when and how the world changes.

We chose this because drawing a person broke the particles' breath, and because one particle set makes a change of kind a continuous motion and leaves one system to build. A webcam later only has to estimate where people are and where they look, which is much cheaper than segmentation.

## Considered Options

- **Person buffer and ID mask (ADR 0001)**: needed to draw figures; nothing here reads a figure, so the mask pass would cost frames for nothing.
- **Two particle systems, cross-faded inside the smoke**: tried in the prototype (round 2); the swap stayed visible and it meant building two systems.
- **Shell particles flowing freely over the surface like the creature's**: the shell wrinkled into creature-like folds and lost its hard outline; each particle keeps a fixed home direction on the shell instead.
