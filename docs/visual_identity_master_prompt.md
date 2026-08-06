# Picross 3D — Visual Identity Master Prompt

## Core Style DNA (Always Include)
Modern minimalist 3D picross/nonogram puzzle cube, rendered as a floating translucent voxel grid of [GRID SIZE, e.g. 5x5x5] cubes. Soft studio lighting, subtle ambient occlusion, gentle glass-like refraction on transparent voxels. Color palette: pale pastel blue and white for inactive/undetermined state, warm saturated orange for confirmed/marked state. Clean sans-serif glowing numeral labels on the top and front faces only, in a soft cyan-blue glow. Background: seamless, softly blurred neutral white/light-gray studio backdrop, no visible horizon line, subtle floor reflection. Rendering style: soft global illumination, low contrast, high-key exposure, slight bloom/glow on emissive elements, physically-based materials (frosted glass + matte ceramic), no harsh shadows, no textures, no visible grid lines beyond the cube bevels themselves. Composition: cube centered, three-quarter isometric-ish perspective, camera slightly above eye level. Overall mood: clean, satisfying, tactile, premium mobile game UI — think Monument Valley meets a glass Rubik's Cube.

**Negative / Avoid**: No photorealistic textures, no dark or moody lighting, no neon cyberpunk saturation, no flat 2D icon style, no visible seams or low-poly faceting, no clutter in background, no extra UI chrome unless specified, no rainbow palette — only blue/white/orange as defined above.

---

## State Modules

### 1. Pristine Puzzle (Idle / Numbering State)
`[CORE STYLE DNA]` +
The full grid is intact and translucent. Every top-face and front-face cell displays a small glowing blue clue number. No cubes are removed, shattered, or marked. Edges of the cube catch a warm rim light on the top corners (subtle warm-white highlight), otherwise the palette stays cool pastel blue/white. This is the "ready to solve" state — crisp, quiet, inviting.

### 2. Destroy Action (Removing a Block)
`[CORE STYLE DNA]` +
A glowing light-pointer/cursor (soft white arrow with a faint blue glow) is actively selecting one voxel at position `[LOCATION]`. That voxel is mid-shatter: it explodes outward into a cloud of small glowing light-blue particles/shards, fading in opacity and scattering with slight motion blur, revealing an empty translucent cavity in the grid behind it. Number labels remain visible and undisturbed on unaffected faces. Particle effect should read as digital/energetic, not physical debris — think dissolving light motes, not rock chunks.

### 3. Mark Action (Flagging a Block as Kept)
`[CORE STYLE DNA]` +
A glowing light-pointer/cursor selects one voxel at position `[LOCATION]`. That voxel transitions from translucent to fully solid, saturated, glowing orange — opaque, matte-ceramic finish, no transparency. Adjacent translucent voxels pick up a faint warm orange bounce-light/reflection on their inner faces, showing the new block's glow spilling into the glass grid around it. No particle effect here — this is a smooth solidify/lock transition, contrasting with the destroy state's explosive one.

### 4. Completion / Reveal
`[CORE STYLE DNA, background and lighting only — grid is now GONE]` +
The translucent grid structure has fully disappeared. In its place, floating in the same studio space, is the finished solid object made of the voxels that remained: `[OBJECT DESCRIPTION, e.g. "a stylized anchor"]`. The object is built from a blend of the two established emissive colors — pastel glowing blue and confirmed glowing orange — arranged to suggest the object's form and shading (blue for shadowed/interior faces, orange for the dominant/"hero" faces). No visible grid lines, no numbers, no cursor. Composition and lighting match the idle state exactly so it reads as the same "camera" resolving to a final answer. Minimalist white background, soft floor reflection beneath the object.

---

## Quick-Use Template

When you need a one-off asset, copy this and fill in the brackets:

```text
[CORE STYLE DNA]

State: [pristine / destroy / mark / reveal]
Grid size: [e.g. 5x5x5]
Object being solved (for reveal only): [e.g. anchor, heart, rocket]
Focus location (for destroy/mark only): [e.g. top-right corner]
Camera: [default three-quarter iso — only change if you need a different angle]
```

---

## Consistency Checklist (Before Accepting an Output)
- [ ] Palette is only pastel blue / white / orange — nothing else
- [ ] Numbers glow blue, are sans-serif, only on top + front faces
- [ ] Transparency reads as glass, not plastic or matte
- [ ] Destroy = particle shatter (blue); Mark = solid glow (orange), no particles
- [ ] Background stays a soft, blurred neutral white — no scenery, no gradients beyond soft vignette
- [ ] Lighting is high-key/bright, no dramatic shadows
- [ ] Reveal state has zero visible grid — only the resolved voxel object
