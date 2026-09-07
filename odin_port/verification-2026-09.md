# Odin dev-2026-09 verification

Tested 2026-09-07 on macOS 26.6.2, arm64, with `/opt/homebrew/bin/odin`:
`dev-2026-09:a2fb372b7`. The supplied Odin checkout is at the same release commit;
the relevant installed Darwin, linalg, allocator, slice-sort, and SIMD sources
were also compared with the checkout and match.

## Demo results

All five variants built without diagnostics using `-vet -strict-style`, rendered
the expected image on screen, and exited with status 0 when their window closed.
Runtime checks enabled both `MTL_DEBUG_LAYER=1` and `MTL_SHADER_VALIDATION=1`;
the logs contained no Metal API or shader validation errors.

| Chapter | Defines | Observed result |
|---|---|---|
| 01-hello-metal | none | Red sphere silhouette |
| 01-hello-metal | `CHALLENGE=true` | Tall green ellipse |
| 02-3d-models | none | Red wireframe train loaded from the original USDZ |
| 02-3d-models | `EXPORT_CONE=true` | Red wireframe cone and successful USDA export |
| 02-3d-models | `CHALLENGE=true` | Red wireframe mushroom loaded from the original USDZ |

The cone export was written in a temporary directory, preserving the existing
export. Its USDA header, mesh, triangle counts, and index bounds were checked.
Temporary `.app` wrappers around the unchanged binaries allowed automated window
inspection. No renderer or Model I/O binding changes were necessary.

The first sandboxed launch could not obtain a Metal device; the runtime checks
therefore ran outside the sandbox with GPU access. This was an execution
environment restriction, not a compiler regression.

A separate sphere run with `OBJC_DEBUG_MISSING_POOLS=YES` emitted warnings.
Two sampled warning backtraces in LLDB originated in Apple's AppIntents /
LinkServices XPC setup on a dispatch worker, with no port frames. This smoke
check is not a comprehensive leak audit; it does not establish that every
warning has the same origin.

To reproduce a build, from `odin_port/`:

```sh
odin build 01-hello-metal -collection:common=common -vet -strict-style -out:/tmp/hello-metal
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 /tmp/hello-metal
```

Repeat with the chapters and `-define:` flags above. At the time of this check,
`run.sh` used the PATH compiler with an `ODIN=/path/to/odin` override. It has since
been replaced by the root [Justfile](../Justfile); see the [current workflow](README.md).

## Library changes worth using

Compared `dev-2026-08..dev-2026-09`, guided by the
[official release notes](https://github.com/odin-lang/Odin/releases/tag/dev-2026-09)
and checked against the actual source diff.

- **Dynamic arena alignment fix:** reused blocks now have their allocation
  address realigned. Useful if later chapters allocate SIMD-aligned CPU data
  from a resettable arena. It does not change Metal buffer layout requirements.
  [PR #7355](https://github.com/odin-lang/Odin/pull/7355).
- **Improved stable sorting:** `core:slice` now uses merge-rotate for larger
  arrays, retaining insertion sort for arrays of at most 200 elements. A useful
  option for later draw lists that need equal-key ordering preserved; no port
  performance benchmark was performed.
  [PR #7349](https://github.com/odin-lang/Odin/pull/7349).
- **More ARM NEON support:** `core:simd/arm` gains table lookup, extended table
  lookup, and logical operations. Potentially useful for measured CPU-side mesh
  or animation bottlenecks on Apple silicon; the current demos need none of it.
  [PR #7256](https://github.com/odin-lang/Odin/pull/7256),
  [PR #7275](https://github.com/odin-lang/Odin/pull/7275),
  [PR #7332](https://github.com/odin-lang/Odin/pull/7332).
- **Interop regression coverage:** the compiler adds an ABI conformance harness
  and more aggregate-passing fixes. Relevant reassurance for future Model I/O
  bindings, but new selectors and signatures still need their own checks.
  [PR #7327](https://github.com/odin-lang/Odin/pull/7327).

There are **no changes to `vendor:darwin` or `core:math/linalg`** between these
releases. Model I/O, MTKMesh, MTKTextureLoader, MPS, and MetalFX coverage has not
been added; our custom bindings remain necessary. The MTKView delegate still
uses an autoreleased NSValue wrapper, so retain it as before. Keep the port's
Metal projection conventions. Foundation's only change skips Cocoa on iOS,
which does not benefit these macOS demos.

September also removes `core:os/old` and the `os.Error == 0` compatibility rule.
Chapter 2 already imports `core:os` and compares errors with `nil`, so it needs
no migration.

## Justfile and AddressSanitizer follow-up

The root [Justfile](../Justfile) replaced `run.sh` on 2026-09-07. With just 1.58.0
and the same Odin release, `just check` passed for all five variants using
`-strict-style -warnings-as-errors`.

All five variants also ran through `just sanitize` with
`-debug -sanitize:address`, Metal API validation, and Metal shader validation.
Temporary copies used the audit's three-frame completion/exit instrumentation;
compile-time assertions verified AddressSanitizer and debug mode were enabled.
Every run completed its frames and exited 0 with no ASan or Metal validation
errors. The temporary cone export did not overwrite the existing repository
export. These are bounded smoke checks, not leak or shutdown-ownership proofs.

Temporary test procedures verified `just test` and `just test-sanitize`, including
the expected debug/sanitizer flags. An executable-path/argument probe checked
`ODIN` overrides containing spaces, quoted argument preservation, compiler-error
propagation, and the working directory when invoked from a chapter directory.
The default recipe and `just --fmt --check` also passed. No permanent unit-test
suite was added; the implemented demos still require runtime/visual checks.
