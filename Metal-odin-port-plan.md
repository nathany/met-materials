# Porting *Metal by Tutorials* (5th ed.) to Odin

A feasibility assessment and working plan for reimplementing the book's Swift/Metal sample
projects in [Odin](https://odin-lang.org), based on a survey of this repo (31 chapters,
72 Xcode projects) and the Odin repo's `core`/`vendor` libraries (as of July 2026).

**Verdict: very feasible.** Odin's `vendor:darwin/Metal` binding covers every GPU feature
the book teaches, through the most advanced chapters (mesh shaders, indirect command
buffers). The ~299 `.metal` shader files — most of the book's real content — port
**unchanged**. The porting work is replacing Apple's *convenience* frameworks: Model I/O's
USD asset pipeline, MetalKit's mesh/texture loaders, and the SwiftUI windowing shell.

---

## 1. What the book depends on

Zero third-party dependencies — 100% Apple frameworks:

| Dependency | Used for | Weight |
|---|---|---|
| **Metal / MetalKit** | everything; `MTKView` (909 refs), `MTKMesh` (379), `MTKTextureLoader` (265) | core |
| **Model I/O** | USD/OBJ import, `MDLVertexDescriptor` (213 refs), procedural primitives (`MDLMesh.newBox`…), `addNormals`/`addTangentBasis`, **skeletal data** (`MDLSkeleton`, `MDLPackedJointAnimation`, ch. 23–24) | heavy |
| **SwiftUI + Observation** | window shell (`NS/UIViewRepresentable` around MTKView), app state | replaceable |
| **GameController** | `GCKeyboard`/`GCMouse` camera input | trivial |
| **simd + MathLibrary.swift** | 236-line column-major math helper, copied into all 60 projects | trivial (see cheat sheet, §5) |
| **MetalPerformanceShaders** | ch. 29 only: Sobel, Gaussian blur, threshold, matrix multiply | isolated |
| **MetalFX** | ch. 30 only: spatial/temporal upscalers | isolated |

Assets: **USDZ dominates** (101 `.usdz` + 48 `.usd/.usda`; only 6 `.obj` in the early
playgrounds), 549 PNG/JPG textures, cube maps as PNG sets in `.xcassets`. No HDR/KTX/glTF.
No GameplayKit, no ray tracing, no physics engine — flocking/particles (ch. 17–18) are
hand-rolled compute shaders and port directly.

## 2. What Odin provides

### Covered well

- **Metal** — `vendor:darwin/Metal`: a metal-cpp-style port, ~9,400 lines, 142 classes.
  Compute, blit, argument buffers, function constants, **indirect command buffers
  (ch. 26)**, **mesh pipelines (ch. 28)**, acceleration structures. Everything bindable.
- **MTKView** — `vendor:darwin/MetalKit` binds `MTKView` plus a working `ViewDelegate`
  bridge (`drawInMTKView` / `drawableSizeWillChange` as Odin callbacks).
- **CAMetalLayer** — `vendor:darwin/QuartzCore`.
- **Windowing** — `vendor:sdl2` / `vendor:sdl3` have first-class Metal surfaces
  (`Metal_CreateView`, `Metal_GetLayer`); GLFW exposes `GetCocoaWindow`; or go native via
  `core:sys/darwin/Foundation` (NSApplication/NSWindow/NSView are all bound).
- **Math** — `core:math/linalg` (+ `glsl`/`hlsl` sub-packages) replaces MathLibrary.swift
  and simd. Column-major native `matrix` type (`#row_major` exists; not needed for Metal).
  See the cheat sheet in §5 — including two conventions traps.
- **Textures** — `vendor:stb/image` decodes PNG/JPG; upload via `texture->replaceRegion`.
- **Noise** — `core:math/noise` (OpenSimplex2), if wanted for terrain experiments.
- **Obj-C interop** — first-class: `@(objc_class)` structs, `->` selector-call sugar,
  blocks (`intrinsics.objc_block`), runtime subclassing (`NS.class_addMethod` etc.) for
  implementing delegates.

### Gaps to engineer around

| Gap                                             | Replacement strategy                                                                                                                                                                                                                                                                                                                            |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Model I/O / USD** (the big one)               | Convert assets once: USDZ → glTF (`usdcat`/Blender CLI/`usd2gltf`), load with `vendor:cgltf`. glTF carries skins + joint animations, so the ch. 23–24 skeletal data survives conversion; keyframe sampling + skinning matrices are hand-written with `linalg` (the book already hand-rolls `AnimationClip` sampling on top of MDL data anyway). |
| `MTKMesh` / `MDLVertexDescriptor`               | Own `Mesh` struct: cgltf accessors → `device->newBufferWithSlice(...)` + a hand-built `MTL.VertexDescriptor`. More explicit than Swift — arguably better pedagogy.                                                                                                                                                                              |
| Model I/O tangent generation                    | MikkTSpace (small C lib, trivial to bind) or export tangents into the glTF.                                                                                                                                                                                                                                                                     |
| Procedural primitives (`newBox`, sphere, plane) | Small generators written once, or export primitives as glTF.                                                                                                                                                                                                                                                                                    |
| `MTKTextureLoader` + mipmaps                    | stb_image → `replaceRegion`; mipmaps via `BlitCommandEncoder->generateMipmaps`. Cube maps: 6 PNG faces → `.Cube` texture slices.                                                                                                                                                                                                                |
| SwiftUI shell                                   | SDL2/SDL3 event loop (recommended), or native NSWindow + MTKView.                                                                                                                                                                                                                                                                               |
| GameController input                            | SDL keyboard/mouse events.                                                                                                                                                                                                                                                                                                                      |
| MPS (ch. 29)                                    | No binding. Write the equivalent compute kernels (blur/Sobel are classic exercises) or hand-bind the few MPS classes (mechanical with Odin's objc attributes).                                                                                                                                                                                  |
| MetalFX (ch. 30)                                | No binding. Skip, or hand-bind `MTLFXSpatialScaler` (small API).                                                                                                                                                                                                                                                                                |

## 3. Gotchas

1. **Manual reference counting.** No ARC. Cocoa rules apply: `alloc`/`new`/`copy` ⇒ you
   `release()`; everything else is autoreleased ⇒ you need an `NS.AutoreleasePool` **per
   frame** (and per thread) or drawables/command buffers leak. Debug with
   `OBJC_DEBUG_MISSING_POOLS=YES`. The #1 bug source coming from Swift.
2. **No automatic shader compilation.** Xcode builds `default.metallib` into the bundle;
   an Odin binary has no bundle. Compile MSL at runtime (`device->newLibraryWithSource`)
   or offline: `xcrun metal -c Shaders.metal -o s.air && xcrun metallib s.air -o default.metallib`,
   then `newLibraryWithFile`.
3. **Stale doc note:** the vendor README says `import MTL "core:sys/darwin/Metal"`; the
   real path is `vendor:darwin/Metal`. Foundation genuinely lives at
   `core:sys/darwin/Foundation`.
4. **Struct layout between CPU and MSL.** MSL `float3` in a buffer is 16-byte aligned.
   Swift's `SIMD3<Float>` happens to have 16-byte stride, but Odin's `[3]f32` is a tight
   12 bytes — mirroring the book's `Common.h` structs requires `[4]f32` or explicit
   padding fields. `matrix[4,4]f32` matches `float4x4` (64 bytes, column-major) directly.
5. **Projection-matrix conventions differ** — `linalg.matrix4_perspective` targets
   OpenGL (right-handed, NDC depth −1..1), Metal wants 0..1 and the book uses a
   left-handed projection. Hand-port the book's four view/projection constructors (§5.4).
6. **Obj-C callbacks are `proc "c"`** — no Odin context inside delegate callbacks; set
   `context = runtime.default_context()` if needed.
7. **Naming:** bindings drop prefixes — `MTL.Device`, `MTL.RenderPassDescriptor`, enum
   cases like `.BGRA8Unorm_sRGB`, `.Triangle`.
8. **Debugging without Xcode:** run with `MTL_DEBUG_LAYER=1` / `MTL_SHADER_VALIDATION=1`;
   GPU capture via attaching Xcode or `MTLCaptureManager` (bound).
9. **Target macOS only.** Odin-on-iOS is rough. All rendering content is platform-neutral;
   the TBDR/imageblock chapters (12–15) just need an Apple-silicon Mac.
10. **`#simd` types do not follow the C vector ABI (verified July 2026, dev-2026-07).**
    Odin passes `#simd[4]f32`/`#simd[2]u32` `proc "c"` parameters in general-purpose
    registers, while clang puts `vector_float3`/`vector_uint2` in SIMD registers
    (AAPCS64 short vectors) — so *every* call into a simd-signature Apple API mis-passes
    its arguments, whether through `intrinsics.objc_send` or a plain `foreign` C import.
    Verified two ways: `MDLMesh initSphereWithExtent:…` crashes with the segments vector
    showing up as an object pointer, and a clang-compiled control function receives
    garbage lanes. No upstream issue exists yet (worth filing). Consequence:
    **hand-binding Model I/O's procedural initializers is off the table in Odin** — the
    workarounds are a clang-compiled shim exposing scalar/pointer parameters only, or
    pure-Odin replacements (mesh generators, cgltf), which is what §2's gap table already
    recommends. Metal itself is unaffected (its API passes structs like `ClearColor`,
    never simd vectors by value).
    **Resolved:** reported as odin-lang/Odin#7010 (2026-07-11); fix PR #7015 (params,
    returns, and vector *aggregates* — `MDLAxisAlignedBoundingBox`-style structs)
    **merged**, ships with dev-2026-08. Verified locally against both repros. The port's
    C shim has been removed — simd-signature selectors are now called directly via
    `objc_send` with `#simd` types (`common/modelio/new_sphere`), and `run.sh` uses the
    locally built compiler until Homebrew ships dev-2026-08. This unblocks direct
    binding of *all* Model I/O simd-signature APIs (procedural primitives, boundingBox,
    animation array getters) — the glTF-conversion strategy in §2 is now optional
    rather than forced.
11. **The vendor `MTKView` delegate bridge vs. autorelease pools** (found porting
    ch. 1): `MTKView.delegate` is a *weak* Obj-C property, and
    `vendor:darwin/MetalKit`'s `View_setDelegate` wraps your Odin `ViewDelegate` struct
    in an **autoreleased `NSValue`**. If you call `setDelegate` inside an autorelease
    pool (which you should be using during setup — see gotcha 1), the wrapper is
    deallocated at pool drain and **drawing silently stops** — no crash, no warning,
    just zero `drawInMTKView` calls. Fix: retain the wrapper right after setting it:
    `intrinsics.objc_send(^NS.Value, view, "delegate")->retain()`. Also remember `main`
    itself needs a setup pool around AppKit/Metal initialization (drained before
    `app->run()`, which manages its own per-event pools); `OBJC_DEBUG_MISSING_POOLS=YES`
    flags the gap. Warnings from Apple-internal worker threads (e.g. the runtime shader
    compiler) are noise you can't fix.

## 4. Port structure (as implemented in `odin_port/`)

- One Odin package per chapter (`01-hello-metal/`, …) plus shared packages under
  `common/`, imported through a collection (`import mdl "common:modelio"`; `run.sh`
  passes `-collection:common=common`). Organizing rule: **`common/` holds only plumbing
  the book hides inside Apple frameworks** (Model I/O bindings + shim; later
  `texture.odin`, `math.odin` §5.4, camera/input); anything the book teaches in-chapter
  stays in the chapter package so each demo reads independently.
- `run.sh <chapter>` compiles any `common/*/*.m` clang shims (needed only because of the
  `#simd` ABI gap, §3.10), then `odin run`s the chapter. Both the shims and the modelio
  bindings are deliberately disposable — the former if the ABI issue is fixed upstream,
  the latter if Odin 2027 ships Obj-C framework coverage; bindings mirror vendor naming
  so migration is an import swap.
- An asset script converting the book's `.usdz` → `.glb` into a shared `assets/` dir.
- Difficulty by chapter: **1–22** (rendering, lighting, shadows, deferred, PBR/IBL,
  tessellation, particles) port nearly 1:1. **23–24** (animation) need the most new code
  (glTF skin/keyframe sampling). **25–28** (bindless, ICB, GPU-driven, mesh shaders) are
  fully supported by the bindings. **29 (MPS)** and **30 (MetalFX)** need hand-bindings
  or substitution.

### Representative-sample plan (agreed 2026-07)

Not porting all 31 chapters — a sample chosen to touch every distinct interop surface
(where SIMD-FFI-class bugs live), skipping chapters that are new shader techniques on
existing plumbing (MSL ports unchanged and exercises Odin not at all).

- **Spine (in order):** 1 ✅ → 2 (MDLAsset I/O, class-as-argument) → 5 (CPU↔GPU structs,
  absorbs 4) → 7 (hand-built vertex descriptors, absorbs 6) → 8 (materials,
  MTKTextureLoader + NSDictionary options) → 9 (GameController: **blocks**,
  NotificationCenter) → 10 (scene consolidation) → 19 (tessellation + first MPS) →
  23+24 (skeletal animation: vector-aggregate `boundingBox`, matrix-array pointer
  getters, protocol queries; hard pair, do together) → 28 (mesh pipeline descriptors —
  likely first-ever user of those vendor bindings) → 29 (MPS class family).
- **Optional:** 21 (`MDLSkyCubeTexture`, `vector_int2` lane type), 26 (ICB — same
  first-user argument as 28), 30 (MetalFX scaler, ~50-line binding).
- **Skip:** 3–4, 6 (subsumed); 11–18, 20, 22 (pure rendering technique, no new interop);
  25, 27 (incremental over 24/26); 31 (no code). Skipping is reversible — a skipped
  technique's shaders drop into the ported engine nearly verbatim.
- Catch-up points where `common/` must leap a gap: 10→19 (small) and 19→23 (needs the
  ch. 8–10 material/camera stack, already in the spine).

## 5. Math cheat sheet: Swift simd / MathLibrary → Odin

### 5.1 Types

| Swift | Odin | Notes |
|---|---|---|
| `float2` / `SIMD2<Float>` | `[2]f32` (`linalg.Vector2f32`) | Odin arrays have full array programming |
| `float3` / `SIMD3<Float>` | `[3]f32` (`linalg.Vector3f32`) | ⚠ 12 bytes in Odin vs 16 in Swift — pad in GPU-shared structs |
| `float4` / `SIMD4<Float>` | `[4]f32` (`linalg.Vector4f32`) | |
| `float3x3` | `matrix[3,3]f32` (`linalg.Matrix3f32`) | column-major |
| `float4x4` | `matrix[4,4]f32` (`linalg.Matrix4f32`) | column-major, layout-compatible with MSL `float4x4` |
| `simd_quatf` | `quaternion128` (`linalg.Quaternionf32`) | built-in language type |
| `matrix_double4x4` | `matrix[4,4]f64` | convert with `linalg.matrix_cast(m, f32)` |
| `SIMD4<Double>` | `[4]f64` | convert with `linalg.array_cast(v, f32)` |

### 5.2 Operators, accessors, free functions

| Swift | Odin |
|---|---|
| `a * b` (matrix × matrix / matrix × vector) | `a * b` (same) |
| `v1 * v2` (component-wise) | `v1 * v2` (same — array programming) |
| `v.xyz` (book's `float4` extension) | `v.xyz` — **built into the language**, any swizzle works |
| `m.columns.3` | `m[3]` (single index = column) ; `m[row, col]` for elements |
| `matrix_identity_float4x4` / `.identity` | `linalg.MATRIX4F32_IDENTITY` (or `matrix[4,4]f32(1)`) |
| `normalize(v)`, `dot`, `cross`, `length`, `distance` | `linalg.normalize`, `.dot`, `.cross`, `.length`, `.distance` |
| `m.inverse`, `m.transpose` | `linalg.inverse(m)`, `linalg.transpose(m)` |
| `π`, `Float.pi` | `math.PI` (`core:math`) |
| `x.degreesToRadians` / `.radiansToDegrees` | `math.to_radians(x)` / `math.to_degrees(x)` |
| `sin`, `cos`, `tan`, `abs`, `max`… | `math.sin`, `math.cos`, … (or builtin `abs`, `max`) |

### 5.3 MathLibrary.swift → `core:math/linalg`, function by function

| MathLibrary (Swift) | Odin |
|---|---|
| `float4x4(translation: t)` | `linalg.matrix4_translate_f32(t)` |
| `float4x4(scaling: s)` (vector) | `linalg.matrix4_scale_f32(s)` |
| `float4x4(scaling: s)` (uniform) | `linalg.matrix4_scale_f32({s, s, s})` |
| `float4x4(rotationX: a)` | `linalg.matrix4_rotate_f32(a, {1, 0, 0})` — same convention, verified against the book's column layout |
| `float4x4(rotationY: a)` | `linalg.matrix4_rotate_f32(a, {0, 1, 0})` |
| `float4x4(rotationZ: a)` | `linalg.matrix4_rotate_f32(a, {0, 0, 1})` |
| `float4x4(rotation: [x,y,z])` (X·Y·Z) | `rx * ry * rz` composed from the above (see `rotation_xyz` in §5.4) |
| `float4x4(rotationYXZ:)` | `ry * rx * rz` (see §5.4) |
| `m.upperLeft` | `linalg.matrix3_from_matrix4(m)` |
| `float3x3(normalFrom4x4: m)` | `linalg.matrix3_inverse_transpose(linalg.matrix3_from_matrix4(m))` |
| `float4x4(projectionFov:…)` | **hand-write** — see §5.4 (`linalg.matrix4_perspective` is GL-style: RH, depth −1..1; Metal needs 0..1 and the book is left-handed) |
| `float4x4(eye:target:up:)` (LH lookAt) | **hand-write** — see §5.4 (`linalg.matrix4_look_at` is the GL right-handed convention) |
| `float4x4(orthographic:near:far:)` | **hand-write** — see §5.4 (`linalg.matrix_ortho3d` is GL depth −1..1) |
| `float4x4(_ m: matrix_double4x4)` | `linalg.matrix_cast(m, f32)` |
| `float4(_ d: SIMD4<Double>)` | `linalg.array_cast(d, f32)` |
| `simd_quatf.identity` | `linalg.QUATERNIONF32_IDENTITY` |
| `simd_quatf(angle:axis:)` | `linalg.quaternion_angle_axis_f32(angle, axis)` |
| `simd_slerp(q1, q2, t)` | `linalg.quaternion_slerp(q1, q2, t)` (also `quaternion_nlerp`) |
| `q.act(v)` (rotate vector) | `linalg.quaternion_mul_vector3(q, v)` |
| `simd_quatf(m)` (from matrix) | `linalg.quaternion_from_matrix3_f32(linalg.matrix3_from_matrix4(m))` |
| `float4x4(q)` (from quaternion) | `linalg.matrix4_from_quaternion_f32(q)` |
| TRS compose (translate·rotate·scale) | `linalg.matrix4_from_trs_f32(t, r, s)` — replaces the book's `Transform.modelMatrix` multiply chain |

### 5.4 Drop-in `common/math.odin` for the Metal-convention constructors

These four are the only MathLibrary pieces `linalg` doesn't cover with matching
conventions. Ported verbatim from the book (column-major; Odin matrix literals are
written row-by-row, so these read transposed relative to the Swift column lists —
the resulting memory layout is identical):

```odin
package common

import "core:math"
import "core:math/linalg"

float3   :: linalg.Vector3f32
float4x4 :: linalg.Matrix4f32

// Left-handed perspective, depth 0..1 (Metal). MathLibrary `projectionFov`.
projection_fov :: proc(fov, near, far, aspect: f32, lhs := true) -> float4x4 {
	y := 1 / math.tan(fov * 0.5)
	x := y / aspect
	z := lhs ? far / (far - near) : far / (near - far)
	w := lhs ? -near * z : near * z
	return {
		x, 0, 0, 0,
		0, y, 0, 0,
		0, 0, z, w,
		0, 0, lhs ? 1 : -1, 0,
	}
}

// Left-handed view matrix. MathLibrary `init(eye:target:up:)`.
look_at :: proc(eye, target, up: float3, left := true) -> float4x4 {
	z := left ? linalg.normalize(target - eye) : linalg.normalize(eye - target)
	x := linalg.normalize(linalg.cross(up, z))
	y := linalg.cross(z, x)
	return {
		x.x, x.y, x.z, -linalg.dot(x, eye),
		y.x, y.y, y.z, -linalg.dot(y, eye),
		z.x, z.y, z.z, -linalg.dot(z, eye),
		0,   0,   0,   1,
	}
}

// Orthographic, depth 0..1 (Metal). MathLibrary `init(orthographic:near:far:)`.
// rect: origin = top-left, like the book's CGRect usage.
orthographic :: proc(left, right, top, bottom, near, far: f32) -> float4x4 {
	return {
		2 / (right - left), 0, 0, (left + right) / (left - right),
		0, 2 / (top - bottom), 0, (top + bottom) / (bottom - top),
		0, 0, 1 / (far - near),   near / (near - far),
		0, 0, 0, 1,
	}
}

// Euler composites matching MathLibrary `rotation` / `rotationYXZ`.
rotation_xyz :: proc(angle: float3) -> float4x4 {
	rx := linalg.matrix4_rotate_f32(angle.x, {1, 0, 0})
	ry := linalg.matrix4_rotate_f32(angle.y, {0, 1, 0})
	rz := linalg.matrix4_rotate_f32(angle.z, {0, 0, 1})
	return rx * ry * rz
}
rotation_yxz :: proc(angle: float3) -> float4x4 {
	rx := linalg.matrix4_rotate_f32(angle.x, {1, 0, 0})
	ry := linalg.matrix4_rotate_f32(angle.y, {0, 1, 0})
	rz := linalg.matrix4_rotate_f32(angle.z, {0, 0, 1})
	return ry * rx * rz
}
```

Everything else in MathLibrary.swift (and far more — quaternion utilities the book
lacks) comes straight from `core:math/linalg`. If you prefer GLSL naming
(`mat4LookAt`, `quatSlerp`, `radians`), `core:math/linalg/glsl` mirrors the same
functionality — but note its projection procs are also GL-convention.

## 6. A small example: clear + triangle (Odin + SDL2 + Metal)

Verified against the actual binding signatures in the Odin repo
(`newLibraryWithSource`, `newBufferWithSlice`, `renderCommandEncoderWithDescriptor`, …).
Build and run with `odin run .` — no Xcode project, no build system.

```odin
package triangle

import "core:fmt"
import NS  "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA  "vendor:darwin/QuartzCore"
import SDL "vendor:sdl2"

shader_source :: `
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
  float4 position [[position]];
  float4 color;
};

vertex VertexOut vertex_main(uint vid [[vertex_id]],
                             constant packed_float3 *positions [[buffer(0)]]) {
  VertexOut out {
    .position = float4(positions[vid], 1.0),
    .color    = float4(positions[vid] * 0.5 + 0.5, 1.0),
  };
  return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
  return in.color;
}
`

main :: proc() {
	SDL.Init({.VIDEO}); defer SDL.Quit()

	window := SDL.CreateWindow("Metal in Odin",
		SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED, 800, 600,
		{.ALLOW_HIGHDPI, .RESIZABLE})
	defer SDL.DestroyWindow(window)

	device := MTL.CreateSystemDefaultDevice()
	defer device->release()
	fmt.println(device->name()->odinString())

	// Attach a CAMetalLayer to SDL's window
	metal_view := SDL.Metal_CreateView(window)
	defer SDL.Metal_DestroyView(metal_view)
	layer := (^CA.MetalLayer)(SDL.Metal_GetLayer(metal_view))
	layer->setDevice(device)
	layer->setPixelFormat(.BGRA8Unorm_sRGB)

	// Compile shaders at runtime (or precompile a .metallib, see §3.2)
	source := NS.String.alloc()->initWithOdinString(shader_source)
	defer source->release()
	library, err := device->newLibraryWithSource(source, nil)
	if err != nil { fmt.eprintln(err->localizedDescription()->odinString()); return }
	defer library->release()

	vertex_fn   := library->newFunctionWithName(NS.AT("vertex_main"))
	fragment_fn := library->newFunctionWithName(NS.AT("fragment_main"))
	defer vertex_fn->release()
	defer fragment_fn->release()

	desc := MTL.RenderPipelineDescriptor.alloc()->init()
	defer desc->release()
	desc->setVertexFunction(vertex_fn)
	desc->setFragmentFunction(fragment_fn)
	desc->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)

	pipeline, pso_err := device->newRenderPipelineState(desc)
	if pso_err != nil { fmt.eprintln(pso_err->localizedDescription()->odinString()); return }
	defer pipeline->release()

	positions := [][3]f32{{0.0, 0.6, 0}, {-0.6, -0.6, 0}, {0.6, -0.6, 0}}
	vertex_buffer := device->newBufferWithSlice(positions[:], {.StorageModeManaged})
	defer vertex_buffer->release()

	queue := device->newCommandQueue()
	defer queue->release()

	for quit := false; !quit; {
		for e: SDL.Event; SDL.PollEvent(&e); {
			#partial switch e.type {
			case .QUIT: quit = true
			}
		}

		// One pool per frame: drains the autoreleased drawable & command buffer
		pool := NS.AutoreleasePool.alloc()->init()
		defer pool->release()

		drawable := layer->nextDrawable()
		assert(drawable != nil)

		pass := MTL.RenderPassDescriptor.renderPassDescriptor()
		color := pass->colorAttachments()->object(0)
		color->setTexture(drawable->texture())
		color->setLoadAction(.Clear)
		color->setClearColor(MTL.ClearColor{0.1, 0.1, 0.12, 1.0})
		color->setStoreAction(.Store)

		cmd := queue->commandBuffer()
		enc := cmd->renderCommandEncoderWithDescriptor(pass)
		enc->setRenderPipelineState(pipeline)
		enc->setVertexBuffer(vertex_buffer, 0, 0)
		enc->drawPrimitives(.Triangle, 0, 3)
		enc->endEncoding()

		cmd->presentDrawable(drawable)
		cmd->commit()
	}
}
```

Compared with the book's ch. 1–3: the Swift `MTKView` + `Renderer` split maps to the SDL
loop + this body; `MTKMesh(mesh:device:)` becomes `newBufferWithSlice`. (An MTKView-based
version is equally possible using the bound `MTK.View` + `ViewDelegate`.)

## 7. Milestones / verification

1. **Triangle** — scaffold §6, `odin run .`; a colored triangle validates toolchain +
   bindings. Run with `MTL_DEBUG_LAYER=1 OBJC_DEBUG_MISSING_POOLS=YES` to confirm clean
   validation and no autorelease-pool leaks.
2. **Asset pipeline** — convert one book model (e.g. `train.usdz`) → `.glb`, load via
   cgltf, render lit with a depth buffer. Proves the entire Model I/O replacement.
3. **Textures + camera** — stb_image upload, mipmaps, `common/math.odin` view/projection;
   equivalent to finishing part I of the book.
4. From there, chapters proceed in book order; shaders copy across as-is.
