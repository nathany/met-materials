# Chapter 2: 3D Models

Follow the pages in this order, running commands from `odin_port/`:

| Swift page | Odin command | Expected result |
|---|---|---|
| [1: Render and Export](<../../02-3d-models/projects/final/Chapter2.playground/Pages/1 Render and Export 3D Model.xcplaygroundpage/Contents.swift>) | `just run 02-3d-models -define:EXPORT_CONE=true` | Red wireframe cone and `generatedCone.usda` |
| [2: Import Train](<../../02-3d-models/projects/final/Chapter2.playground/Pages/2 Import Train.xcplaygroundpage/Contents.swift>) | `just run 02-3d-models` | Red wireframe train |
| [Challenge: Import Mushroom](<../../02-3d-models/projects/challenge/Chapter2.playground/Pages/Import Mushroom.xcplaygroundpage/Contents.swift>) | `just run 02-3d-models -define:CHALLENGE=true` | Red wireframe mushroom |

The defines select separate book examples; do not enable both at once. Export
overwrites `odin_port/generatedCone.usda`, rather than writing into the Swift
playground's shared-data directory. Imports use the original repository USDZ
assets; `just` sets the working directory needed by their relative paths.

## Reading map

In [main.odin](main.odin), `renderer_init` selects procedural cone/export or
asset import with a position vertex descriptor. Both paths converge at MTKMesh
conversion and pipeline setup. The export occurs before that conversion in
Odin; Swift converts first, then exports the same MDLMesh. The remaining setup
and `draw` follow the chapter 1 structure, with wireframe drawing and a submesh
loop. AppKit and the continuous MTKView delegate replace the playground shell.

Both imported pages use the first MDLMesh and draw all of its submeshes, just as
Swift does. The tested train has six submeshes; the mushroom has one. The cone
also uses the loop in Odin; Swift selects its first submesh. The generated cone
has one, so this does not change the example's output.

The imports request a 12-byte position stride (`size_of([3]f32)`) instead of
Swift's 16-byte SIMD3 stride. The vertex descriptor makes this valid and preserves
the shader's `.Float3` input. GPU-shared structs need a separate layout review;
do not copy this stride into a `Common.h` translation. The `position.y -= 1.0`
shader adjustment and red wireframe appearance are preserved.

Both vertex and index buffers preserve their MetalKit offsets. The vertex offset
is a small improvement over Swift's zero assumption, allowing shared Metal
buffers whose mesh data begins at a nonzero offset.

## Ownership to notice

`when` is compile-time selection and does not introduce a scope: the asset and
MDLMesh `defer` calls run when `renderer_init` finishes. The owned MTKMesh remains
alive for the whole process, preserving the buffers cached in `Renderer`.
The Odin submesh array also persists until process exit. These are bounded in
this single-initialization example; they need explicit destruction before a
reloadable renderer is introduced. See the [audit](../audit-2026-09.md) for the
original findings and their evidence; current statuses are in
[KNOWN_ISSUES.md](../../KNOWN_ISSUES.md).
