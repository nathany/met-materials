# Metal by Tutorials — Odin ports

Odin ports of the book's sample projects, following
[Metal-odin-port-plan.md](../Metal-odin-port-plan.md). One Odin package per chapter.

```sh
cd odin_port/01-hello-metal
./build.sh                          # final: red sphere
./build.sh -define:CHALLENGE=true   # challenge: green ellipse
```

The build script exists only to compile the Objective-C shim before `odin run .`
(see below). Run with Metal validation while developing:

```sh
MTL_DEBUG_LAYER=1 OBJC_DEBUG_MISSING_POOLS=YES ./build.sh
```

## Chapters

| Package | Book project | Notes |
|---|---|---|
| [01-hello-metal](01-hello-metal/) | ch. 1 playgrounds (final + challenge) | Native AppKit + MTKView shell; hand-bound Model I/O/MTKMesh sliver (`modelio.odin`); clang shim for the simd-signature sphere initializer (`shim/sphere_shim.m`) |

## Why there's a C shim

Odin's `#simd` types do not follow the C vector calling convention on arm64
(passed in general-purpose instead of SIMD registers — verified against both
`objc_msgSend` and a clang-compiled control function; see plan §3.10). Any
Apple API whose signature contains `vector_float3`-style parameters therefore
can't be called from Odin directly. The shim exposes those calls with
scalar-only signatures. Everything with simd-free signatures (all of Metal,
MTKView, and the `MTKMesh`/`MDLMesh` accessors) is hand-bound in pure Odin
using the same `@(objc_class)` pattern as `vendor:darwin/Metal`.
