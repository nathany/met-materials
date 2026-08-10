# Metal by Tutorials — Odin ports

Odin ports of the book's sample projects, following
[Metal-odin-port-plan.md](../Metal-odin-port-plan.md).

## Layout

```
odin_port/
  run.sh              build + run a chapter
  common/             shared packages replacing Apple convenience frameworks
    modelio/          hand-bound Model I/O / MTKMesh sliver
  01-hello-metal/     one package per chapter
  02-3d-models/
```

**Compiler requirement:** the port needs the `#simd` C-ABI fix
([odin-lang/Odin#7010](https://github.com/odin-lang/Odin/issues/7010), merged via
[PR #7015](https://github.com/odin-lang/Odin/pull/7015), ships with dev-2026-08).
`run.sh` defaults to the locally built compiler at
`~/src/github.com/odin-lang/Odin/odin`; once your PATH compiler is new enough,
run with `ODIN=odin ./run.sh …`.

The organizing rule: **`common/` holds only plumbing the book hides inside
Apple frameworks** (Model I/O bindings, later texture loading, math
constructors). Anything the book teaches in-chapter stays in that chapter's
package, so each demo remains independently readable.

Chapters import shared packages through a collection:
`import mdl "common:modelio"` (mapped by `run.sh` via
`-collection:common=common`).

## Running

```sh
cd odin_port
./run.sh 01-hello-metal                          # final: red sphere
./run.sh 01-hello-metal -define:CHALLENGE=true   # challenge: green ellipse
./run.sh 02-3d-models                            # import train.usdz
./run.sh 02-3d-models -define:EXPORT_CONE=true   # render + export generatedCone.usda
./run.sh 02-3d-models -define:CHALLENGE=true     # import mushroom.usdz
```

With Metal validation while developing:

```sh
MTL_DEBUG_LAYER=1 OBJC_DEBUG_MISSING_POOLS=YES ./run.sh 01-hello-metal
```

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

These bindings deliberately mirror vendor naming, so if Odin 2027's "full
core Objective-C library" effort ships Model I/O coverage, migration is an
import swap and this package gets deleted.
