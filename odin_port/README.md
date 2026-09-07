# Metal by Tutorials — Odin reference implementations

Odin reference implementations that keep near parity with the book's Swift
examples, following [Metal-odin-port-plan.md](../Metal-odin-port-plan.md).
Readers may review and run them, and choose whether to write their own versions
for educational purposes. See [known issues](../KNOWN_ISSUES.md) before using
the current implementations as a reference.

## Layout

The root [Justfile](../Justfile) provides the run, check, and sanitizer commands.
Install `just` and Odin on PATH before using them.

```
odin_port/
  common/             narrow bindings and support for Apple frameworks
    modelio/          hand-bound Model I/O / MTKMesh sliver
  01-hello-metal/     one package per chapter
  02-3d-models/
```

**Compiler requirement:** the port needs the `#simd` C-ABI fix
([odin-lang/Odin#7010](https://github.com/odin-lang/Odin/issues/7010), merged via
[PR #7015](https://github.com/odin-lang/Odin/pull/7015) and included in dev-2026-08).
The root [Justfile](../Justfile) defaults to `odin` on PATH (verified with dev-2026-09).
To test another compiler, run with `ODIN=/path/to/odin just run …`.

The organizing rule: **`common/` holds only plumbing the book hides inside
Apple frameworks** (Model I/O bindings and later MetalKit texture-loading
bindings). Anything the book teaches in-chapter stays in that chapter's package,
so each demo remains independently readable. Math helpers may be shared after
their conventions have been introduced; camera and rendering lessons should
remain visible in their chapters.

Chapters import shared packages through a collection:
`import mdl "common:modelio"` (mapped by `just` via
`-collection:common=common`).

## Running

Run these commands from the repository root or `odin_port/`. The Justfile always
uses `odin_port/` as the working directory so the original asset paths resolve.

```sh
just run 01-hello-metal                          # final: red sphere
just run 01-hello-metal -define:CHALLENGE=true   # challenge: green ellipse
just run 02-3d-models -define:EXPORT_CONE=true   # render + export generatedCone.usda
just run 02-3d-models                            # import train.usdz
just run 02-3d-models -define:CHALLENGE=true     # import mushroom.usdz
```

Chapter 2's commands above follow the book's page order: export, then import.
Export writes (and overwrites) `odin_port/generatedCone.usda`.

With Metal validation while developing:

```sh
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 just run 01-hello-metal
```

## Checks and sanitizers

```sh
just check                                      # all five variants
just check-chapter 02-3d-models -define:CHALLENGE=true
just sanitize 01-hello-metal
just sanitize 01-hello-metal -define:CHALLENGE=true
just sanitize 02-3d-models -define:EXPORT_CONE=true
just sanitize 02-3d-models
just sanitize 02-3d-models -define:CHALLENGE=true
```

`check` runs `odin check -strict-style -warnings-as-errors` for each variant;
it does not build or run an executable. `sanitize` builds and runs a demo with
`-debug -sanitize:address`. Close its window normally after inspecting it.
All run/test recipes also enforce strict style and warnings as errors, and
forward additional arguments without splitting quoted paths or values.

Combine AddressSanitizer with GPU validation when changing memory or interop:

```sh
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 just sanitize 02-3d-models
```

For Odin packages containing `@(test)` procedures, use `just test <package>` or
`just test-sanitize <package>`. Package paths are relative to `odin_port/` (or
absolute); both accept extra Odin flags. `test-sanitize` adds the same debug and
AddressSanitizer flags. The current demos contain no unit tests: invoking Odin's
test runner on them does not exercise their windows or draw callbacks.

AddressSanitizer checks instrumented CPU memory accesses, not shader memory or
all Objective-C/framework ownership. Keep Metal validation and the ownership
checks in the [known issues](../KNOWN_ISSUES.md). Use
`OBJC_DEBUG_MISSING_POOLS=YES` separately when investigating autorelease pools;
it serves a different purpose. `just` with no arguments lists the recipes.

See the [dev-2026-09 verification](verification-2026-09.md) for the five-variant
runtime check and a review of relevant bundled library changes.
The [code and plan audit](audit-2026-09.md) records the original findings and
memory/layout checks; the [fix verification](fix-verification-2026-09.md) records
their resolution. Each chapter README links its exact Swift references
and explains the deliberate differences.

## Chapters

| Package | Book project | Notes |
|---|---|---|
| [01-hello-metal](01-hello-metal/) | ch. 1 playgrounds (final + challenge) | Native AppKit + MTKView shell; Model I/O via `common:modelio` |
| [02-3d-models](02-3d-models/) | ch. 2 playgrounds (two final pages + challenge) | Procedural cone/export; position-only USDZ import; every imported submesh rendered |

## About `common/modelio`

Odin's vendor libraries bind Metal and MTKView but not Model I/O or the
MTKMesh loaders, so this package hand-binds the needed sliver using the same
`@(objc_class)` / `objc_send` pattern as `vendor:darwin/Metal` — including
simd-signature calls like the sphere and cone initializers, which is why the port needs
the `#simd` ABI fix above. (The port originally worked around that compiler
bug with a clang-compiled shim; the bug was found by this port, filed as
#7010, and fixed upstream within a day — the shim is gone.)

These bindings follow the vendor style. If Odin adds equivalent framework
coverage, compare names, signatures, ownership, and tested behavior before
replacing this package. There is no assumed release date for that migration.
