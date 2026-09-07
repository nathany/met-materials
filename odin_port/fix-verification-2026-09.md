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
