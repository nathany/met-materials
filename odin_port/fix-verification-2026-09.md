# Known-issue fix verification — 2026-09-07

Environment: macOS arm64, Odin `dev-2026-09:a2fb372b7`. Each fix runs
`just check` across the five valid configurations. Runtime checks use
`-strict-style -warnings-as-errors -debug -sanitize:address` with
`MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1`, outside the sandbox for GPU access.

Temporary source copies in `/tmp/met-fixes` preserve the chapter examples and
existing cone export. The harness waits for GPU completion and checks command
status for three frames after setup pools drain. It copies the final drawable
into a shared buffer before presentation, then compares its BGRA pixels against
baseline commit `e906649`. The five baseline images were also visually inspected:
red sphere, green ellipse, and red wireframe train, cone, and mushroom.
Pixel comparisons use identical capture instrumentation on both revisions.

## KI-001: Command-creation diagnostics

- All five variants pass `just check`, render identical pixels, and exit 0.
- No AddressSanitizer or Metal validation errors in successful runs.
- In temporary copies of both chapters, force each queue, command buffer, and
  render encoder result to nil immediately before its check. All six runs fail
  with the corresponding diagnostic instead of continuing silently.
- Force a nil descriptor on the first callback and a nil drawable on the second.
  Both chapters skip those callbacks and render the unchanged image on the third.

Harness commands: `python3 /tmp/met-fixes/verify.py fix1`, then the `fail-queue`,
`fail-buffer`, `fail-encoder`, and `skip` modes with `sphere train` arguments.
The harness is temporary test instrumentation, not part of the chapter API.

## KI-002: Vertex-buffer offsets

- All five variants pass `just check` and the ASan/Metal validation runtime checks.
  Their captured pixels match the baseline byte for byte.
- Temporary instrumentation uses `MTKMeshBufferAllocator.newZone:` and
  `newBufferFromZone:length:type:` to allocate padding followed by the vertex
  data. Copy the original bytes into that allocation and substitute the actual
  MTKMeshBuffer before the renderer extracts its buffer and offset. Assert that
  the reported offset is nonzero. All five images still match the baseline.
- As a negative control, bind that same buffer at zero in the sphere and train.
  Both yield the clear-color image, rather than the baseline geometry. The
  padding is larger than the mesh so zero binding cannot accidentally produce
  a similar silhouette from shifted vertices.

Harness modes: `fix2`, `offset`, and `offset-broken sphere train`. The temporary
zone allocation is test input, not a new production allocator or asset path.

## KI-003: Ownership and shutdown

The owned MTKMesh now survives setup as an explicit renderer field and is released
by `renderer_destroy`, together with its queue and pipeline. Borrowed references
are reset. Chapter 2 reads submeshes directly from the mesh, removing the Odin
allocation and its stale-list risk. `Application_State` holds the shell owners;
`applicationWillTerminate` calls `app_shutdown`. The shutdown pauses the view,
clears the actual Objective-C delegate, and releases its wrapper and shell owners.
`setReleasedWhenClosed(false)` keeps the window's release under this owner.

- All five configurations pass `just check`. The initial windowed ASan/Metal
  validation runs with the ownership fix produced byte-identical baseline images
  and exited 0 through AppKit termination (`fix3` mode).
- All five variants pass three init/destroy cycles before a final initialization.
  Temporary associated-object deallocation observers confirm destruction of all
  three meshes, queues, and pipelines, not merely clearing their Odin pointers.
  The train consistently has six submeshes; every other variant has one.
- Calling destruction twice is safe. After the final initialization, calling
  application shutdown twice releases the fourth mesh, queue, and pipeline plus
  the view, window, delegate wrapper, and application delegate. A short run-loop
  drain allows AppKit's pending releases to finish before checking deallocation.
  The system Metal device's explicit owned reference is balanced by source
  review; the process-wide device is not expected to deallocate in this probe.
- Actual `performClose:` events on all five application windows invoke the
  termination callback and exit 0. Assertions verify that the view is paused,
  its Objective-C delegate is nil, and renderer state is cleared during shutdown.
- Both chapters also pass `stop:`/event-wakeup tests: `app->run()` returns and the
  fallback cleanup runs. Repeated cleanup remains safe.
- Both chapters' native close paths pass with `NSZombieEnabled=YES`, without
  messages to deallocated objects. No ASan or Metal validation errors were found
  in the successful runs.
- All five variants additionally render into an offscreen texture while releasing
  renderer owners immediately after the third command buffer is committed and
  before waiting for completion. GPU completion succeeds and the captured pixels
  match the windowed baseline exactly. This exercises the default command buffer's
  strong resource references during teardown.

The desktop session locked during this verification, suspending MTKView draw
callbacks. Those timed-out GUI runs were not counted as passes. Subsequent
lifetime/close/stop checks require no draw callbacks; the final GPU check uses an
explicit 1000-by-1000 render target with the same format, clear color, and draw
commands. No security/session settings were changed. The original windowed
comparisons and this offscreen comparison are separate evidence.

Harness modes: `lifecycle-only`, `close-only`, `stop-only sphere train`, and
`offscreen-inflight`; repeat `close-only sphere train` with `NSZombieEnabled=YES`.
All instruments remain in `/tmp/met-fixes`. These focused ownership checks do
not claim that Apple's frameworks retain no caches or that ASan detects leaks.
