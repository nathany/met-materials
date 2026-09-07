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

Setup and each draw have an autorelease pool. `Renderer` owns the MTKMesh,
command queue, and pipeline; its cached GPU buffers borrow from that mesh.
`renderer_destroy` releases those owners and resets the borrowed references.
Stop drawing before destruction; initialization requires an empty renderer.

`Application_State` owns the window, view, device, and delegate references.
`app_shutdown` pauses the view, clears its weak Objective-C delegate, and releases
the renderer and shell. It runs from `applicationWillTerminate`, including when
the last window closes, since AppKit may never return from `app->run()`.
The window disables release-on-close so this explicit shutdown owns the release.
The retained view-delegate wrapper survives the setup pool and is released only
after detachment. Default Metal command buffers keep encoded resources alive
until their GPU work finishes.
