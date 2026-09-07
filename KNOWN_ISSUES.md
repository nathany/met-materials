# Known issues — Odin reference implementation

Last evaluated: 2026-09-07. Scope: the Odin chapters and their supporting plan,
not the upstream Swift materials. This registry records findings before the
implementation fixes. The [audit](odin_port/audit-2026-09.md) contains supporting
ownership, layout, math, and runtime evidence.

The port is a reference implementation that readers may review or run alongside
*Metal by Tutorials*, fifth edition. Writing their own version is optional.
Review criteria are correctness, clear ownership, useful failure diagnostics,
idiomatic Odin, and near parity with the corresponding Swift example. Small
correctness improvements should be explained; a second engine or asset pipeline
should not be introduced just to address advice about an obsolete example.

## Open implementation findings

| ID | Priority | Finding | Status |
|---|---|---|---|
| KI-001 | P2 | Missing command-creation failure checks | Open; accepted |
| KI-002 | P2 | Vertex-buffer offsets are discarded | Open; accepted |
| KI-003 | P2 | Renderer ownership and destruction are incomplete | Open; accepted for reference quality |

P2 means a correction planned for the reference implementation, not a claim
that the supplied demos currently crash. All five variants rendered in the
earlier verification; none of these source fixes has been applied yet.

### KI-001: Missing command-creation failure checks

**Locations:** `renderer_init` and `draw` in
[chapter 1](odin_port/01-hello-metal/main.odin) and
[chapter 2](odin_port/02-3d-models/main.odin).

`newCommandQueue`, `commandBuffer`, and
`renderCommandEncoderWithDescriptor` results are unchecked. If creation fails,
later Objective-C messages to nil can do nothing, leaving a blank/stale window.
The corresponding Swift pages force-unwrap or guard these results.

**Planned correction:** restore explicit failure checks and a useful diagnostic.
Establish an Odin context before context-dependent assertions/formatting in the
C draw callbacks. Continue skipping frames when the drawable or render-pass
descriptor is temporarily unavailable; that existing behavior is appropriate.

**Acceptance:** build and run all five variants with Metal validation; exercise
the failure paths with controlled test instrumentation and verify a diagnostic
instead of silent continuation. A temporarily unavailable drawable must still
skip the frame safely.

### KI-002: Vertex-buffer offsets are discarded

**Locations:** vertex-buffer extraction in `renderer_init` and `setVertexBuffer`
in both [chapter 1](odin_port/01-hello-metal/main.odin) and
[chapter 2](odin_port/02-3d-models/main.odin).

The code caches `MTKMeshBuffer.buffer` but binds it at offset zero. Apple's
MetalKit `MTKModel.h` explicitly permits several MTKMeshBuffers to share a Metal
buffer at different offsets. A nonzero-offset allocation would read the wrong
vertex region. The index-buffer path already preserves its offset.

**Evidence and scope:** all five supplied variants reported vertex offset zero
in the audit. This assumption is also present in the Swift pages. It is a latent
correctness issue, not an observed image difference with those assets.

**Planned correction:** preserve/use the reported vertex offset, documenting this
small improvement over the Swift example. Keep the chapter's mesh/shader behavior.

**Acceptance:** preserve the five current images and validate a controlled case
with nonzero vertex-buffer offset. Do not count the current zero-offset assets
alone as verification of the fix.

### KI-003: Renderer ownership and destruction are incomplete

**Locations:** `Renderer`, `renderer_init`, and application/delegate setup in
[chapter 1](odin_port/01-hello-metal/main.odin) and
[chapter 2](odin_port/02-3d-models/main.odin).

The owned MTKMesh is kept alive but its owner pointer is discarded. Queues,
pipelines, shell references, and retained view-delegate wrappers have no explicit
shutdown path; chapter 2 also never deletes its dynamic submesh array. The mesh
retention currently keeps cached borrowed buffers valid. Adding a local
`defer mesh->release()` alone would invalidate them after initialization.

These allocations are bounded in the current single-initialization applications.
The audit found no explicit per-frame retain or Odin-array allocation in `draw`;
this is not evidence of a growing per-frame leak. Reinitialization would leak
more owners, and chapter 2 would append to its existing submesh list.

**Planned correction:** retain explicit owners, pair initialization with
destruction, and delete/reset any Odin-owned containers. Consider retaining the
MTKMesh and iterating its submeshes directly, which resembles Swift and avoids
duplicating mesh metadata. Pause/detach the view before releasing the renderer
and the delegate wrapper. Use a shutdown path that actually runs: AppKit's
`terminate:` can exit without returning from `app->run()`, so main-scope defers
alone do not establish cleanup. Handle window-close ownership deliberately.

**Acceptance:** verify normal close/shutdown and balanced ownership under focused
instrumentation. If repeated initialization is supported, check that the second
initialization does not grow the draw list or retain the first mesh's resources.
Otherwise keep its single-initialization contract explicit. Preserve rendering
after setup pools drain and introduce no message-to-deallocated-object failures.

**Priority note:** the original audit called this P3 for a one-shot demo. The
reference-implementation criterion raises it to planned P2 work: readers should
see a usable ownership pattern, even though the runtime evidence has not changed.

## CodeRabbit review of PR #1

Evaluated the [three inline comments and one additional review comment](https://github.com/nathany/met-materials/pull/1#pullrequestreview-5134070961)
against PR head `46cfde6089e72a3f1a5cb7fa3022588e87e0bdae`, and against the local
working tree. Local HEAD is `33d8cc9`; the plan rewrite from the audit is still
uncommitted. CodeRabbit reviewed the older plan, before that rewrite.

All four observations are valid for the reviewed text. Their disposition below
is **addressed in the local plan revision**, not fixed/published in GitHub. The
three inline threads were still unresolved when read. This evaluation does not
post replies, change thread state, or apply CodeRabbit's embedded agent prompts.

| Review comment | Assessment under our criteria | Current disposition |
|---|---|---|
| [CR-001: `usdcat` as a USD-to-glTF converter](https://github.com/nathany/met-materials/pull/1#discussion_r3951487439) | Accept the correction: standard `usdcat` handles USD output; it is not the proposed GLB exporter. Near parity favors loading the original USDZ with Model I/O. | Addressed locally by removing the converter recommendation and making direct Model I/O the plan. Do not add Blender/export tooling to this reference implementation. |
| [CR-002: unchecked SDL initialization/window creation](https://github.com/nathany/met-materials/pull/1#discussion_r3951487443) | Accept for the old SDL sketch: dependent resources must not be used after startup failure. | Addressed locally by removing the separate SDL example. No SDL code exists in the implemented chapters. Their separate Metal command-creation checks remain KI-001. |
| [CR-003: asserting on nil `nextDrawable()`](https://github.com/nathany/met-materials/pull/1#discussion_r3951487447) | Accept for the old continuous SDL loop: a drawable timeout should allow recovery. | Addressed locally by removing that sketch. Both actual MTKView callbacks already return when the descriptor or drawable is nil; retain that behavior. |
| [CR-004: undocumented SDL2 linker dependency](https://github.com/nathany/met-materials/pull/1#pullrequestreview-5134070961) | Accept for the old sketch: Odin's macOS SDL2 binding imports `system:SDL2`; installing the compiler alone does not supply that system library. | Addressed locally by removing the SDL example. Adding an SDL2 installation prerequisite to the native reference implementations would be misleading. |

Verification used the old plan at the reviewed commit, the current chapter
callbacks, the installed Odin SDL2 bindings, and Apple's `CAMetalLayer.h`
declaration documenting nullable/timeout behavior. Independent documentation:
[OpenUSD usdcat](https://openusd.org/release/toolset.html#usdcat),
[SDL_Init](https://wiki.libsdl.org/SDL2/SDL_Init), and
[SDL_CreateWindow](https://wiki.libsdl.org/SDL2/SDL_CreateWindow).
The review's displayed shell scripts and output lengths do not establish a
successful runtime reproduction; no omitted script output was assumed.

CodeRabbit's suggested fixes should therefore not be applied verbatim to the
current tree: they would restore or document a discarded architecture. Its
reported checks also do not establish Odin correctness: docstring analysis
reported zero functions, and several checks were explicitly skipped. The local
compiler, runtime, layout, and Swift-parity checks remain the relevant evidence.

## Other audit findings and diagnostic limits

- **Corrected locally in the prior plan audit:** 36-byte Odin versus 48-byte
  Metal/Swift float3x3 layout; 16-byte GPU alignment requirements; identity-cast
  syntax; Euler versus quaternion TRS guidance; MPS first use in chapter 19;
  obsolete conversion strategy and unsupported coverage/migration promises.
  These are documentation corrections, not fixes to already-ported uniform code.
- **Not a bug:** Odin's `when` introduces no scope. Chapter 2's `defer` calls run
  after mesh conversion, at the end of `renderer_init`.
- **Intentional parity:** imports select the first MDLMesh; their 12-byte packed
  position stride is described by the vertex descriptor; the train draws all six
  of its submeshes. These examples are not general scene importers.
- **Diagnostic caveats, not confirmed port defects:** sampled missing-pool
  warnings originated in Apple's AppIntents/XPC workers. A zombie-instrumented
  train run also emitted a duplicate `_NSZombie_CFReadStream` class warning.
  Neither establishes a defect in the port, and neither should be silently
  counted as proof of clean diagnostics. Further attribution is needed if they
  become reproducible blockers. Zombie mode is not a leak measurement.

When fixing an issue, retain its ID, record the validating evidence, and update
its status. Keep the dated [audit](odin_port/audit-2026-09.md) and
[verification report](odin_port/verification-2026-09.md) as historical evidence.
