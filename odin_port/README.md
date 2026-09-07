# Metal by Tutorials — Odin reference implementations

Odin reference implementations that keep near parity with the book's Swift
examples. Readers may review and run them, and choose whether to write their
own versions for educational purposes. The [Odin supplementary guide](../Metal-Odin-Guide.md)
explains language and framework differences alongside the book.

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

**Requirements:** macOS with a Metal-capable GPU, Xcode's command-line tools and
SDKs, Odin **dev-2026-09 or newer**, and `just` on PATH. The root
[Justfile](../Justfile) uses `odin` on PATH. To select another compiler, run with
`ODIN=/path/to/odin just run …`.

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

Close a demo's window to exit. Chapters 1–2 have no keyboard or mouse controls.
Each chapter README describes its variants, expected output, and any controls.

Chapter 2's commands above follow the book's page order: export, then import.
Do not combine its `EXPORT_CONE` and `CHALLENGE` defines.
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
each define selects its own compile-time branches, so checking one variant does
not type-check every variant. It does not build or run an executable. `sanitize`
builds and runs a demo with `-debug -sanitize:address`. Close its window normally after inspecting it.
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
all Objective-C/framework ownership. Keep Metal validation enabled for GPU checks;
use `OBJC_DEBUG_MISSING_POOLS=YES` separately when investigating autorelease pools.
`just` with no arguments lists the recipes.

A sandbox may hide the Metal device, and a locked desktop may suspend window draw
callbacks. A successful build alone does not confirm that a demo rendered.

Each chapter README links its exact Swift references and explains deliberate
differences in the Odin implementation.

## Chapters

| Package | Book project | Notes |
|---|---|---|
| [01-hello-metal](01-hello-metal/) | ch. 1 playgrounds (final + challenge) | Native AppKit + MTKView shell; Model I/O via `common:modelio` |
| [02-3d-models](02-3d-models/) | ch. 2 playgrounds (two final pages + challenge) | Procedural cone/export; position-only USDZ import; every imported submesh rendered |

## About `common/modelio`

The dev-2026-09 vendor packages provide Metal and MTKView bindings. This package
adds the Model I/O and MTKMesh APIs used by these examples, following the same
`@(objc_class)` / `objc_send` pattern. It includes the SIMD arguments required by
the sphere and cone initializers.

As Odin gains equivalent framework coverage, these declarations can be replaced
with supplied bindings after checking signatures, ownership, and behavior.
