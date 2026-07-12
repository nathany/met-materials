# Metal by Tutorials — Odin ports

Odin ports of the book's sample projects, following
[Metal-odin-port-plan.md](../Metal-odin-port-plan.md).

## Layout

```
odin_port/
  run.sh              build + run a chapter (compiles common/ shims first)
  common/             shared packages replacing Apple convenience frameworks
    modelio/          hand-bound Model I/O / MTKMesh sliver + clang shim
  01-hello-metal/     one package per chapter
```

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
```

With Metal validation while developing:

```sh
MTL_DEBUG_LAYER=1 OBJC_DEBUG_MISSING_POOLS=YES ./run.sh 01-hello-metal
```

## Chapters

| Package | Book project | Notes |
|---|---|---|
| [01-hello-metal](01-hello-metal/) | ch. 1 playgrounds (final + challenge) | Native AppKit + MTKView shell; Model I/O via `common:modelio` |

## Why there's a C shim (and why `common/` may shrink)

Odin's `#simd` types do not follow the C vector calling convention on arm64
(passed in general-purpose instead of SIMD registers — verified against both
`objc_msgSend` and a clang-compiled control function; see plan §3.10, and the
upstream issue filed against odin-lang/Odin). Any Apple API whose signature
contains `vector_float3`-style parameters therefore can't be called from Odin
directly; `common/modelio/sphere_shim.m` exposes those calls with scalar-only
signatures, and `run.sh` compiles it with clang before `odin run`.

Everything with simd-free signatures (all of Metal, MTKView, the
`MTKMesh`/`MDLMesh` accessors) is hand-bound in pure Odin using the same
`@(objc_class)` pattern as `vendor:darwin/Metal`.

Both halves of `common/modelio` are candidates for deletion: the shim goes
away if the `#simd` ABI issue is fixed (the calls become plain `objc_send`),
and the bindings go away if Odin 2027's "full core Objective-C library"
effort ships Model I/O coverage. The bindings deliberately mirror the vendor
naming style so that migration would be an import swap.
