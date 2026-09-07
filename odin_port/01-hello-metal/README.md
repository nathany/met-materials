# Chapter 1: Hello, Metal!

Read beside the Swift [final playground](../../01-hello-metal/projects/final/Chapter1.playground/Contents.swift)
or [challenge playground](../../01-hello-metal/projects/challenge/Chapter1.playground/Contents.swift).

From `odin_port/`:

```sh
just run 01-hello-metal
just run 01-hello-metal -define:CHALLENGE=true
```

The final draws a solid red sphere silhouette on pale yellow. The challenge
changes its extent and fragment color to draw a tall green ellipse. There is
no lighting yet; the flat appearance matches the playground.

## Reading map

1. In [main.odin](main.odin), the constants and shader source correspond to the
   playground's sphere parameters and inline Metal source.
2. `renderer_init` follows mesh allocation, Model I/O → MTKMesh conversion,
   shader compilation, and pipeline creation. `common:modelio` supplies the
   missing Apple bindings; it does not replace the geometry algorithm.
3. `draw` corresponds to the playground's command encoding and presentation.
4. `main` supplies AppKit's window and the MTKView delegate in place of
   `PlaygroundPage.current.liveView`.

The delegate redraws continuously instead of submitting just one frame. The
pipeline uses the view's pixel format, whose default matches the Swift example.
Both vertex and index buffers use their reported offsets. Preserving the vertex
offset is a small correctness improvement over Swift: MetalKit may allocate
several mesh buffers inside one Metal buffer. The supplied sphere uses offset
zero and one submesh.

## Ownership to notice

Setup and each draw have an autorelease pool. The MTKMesh is deliberately kept
alive for the whole process, preserving the borrowed GPU buffers cached in
`Renderer`. The command queue, pipeline, and shell also have process lifetimes.
The retained delegate wrapper is necessary because MTKView holds it weakly.
This is a one-window example, not a reloadable renderer; see the
[audit](../audit-2026-09.md) before reusing its ownership pattern.
