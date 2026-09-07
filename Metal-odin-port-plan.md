# Odin reference implementation of *Metal by Tutorials* (5th ed.)

This port provides an Odin reference implementation of the book's Swift examples.
The goal is near parity in rendering, assets, and concepts, expressed with Odin
structs, procedures, and explicit ownership. Readers may review and run these
implementations alongside the book, and choose whether to write their own for
educational purposes. This document maps the reference code to the book; it is
not a required sequence of implementation exercises.

As of September 2026, chapters **1 and 2** are implemented and their five variants
run with Odin dev-2026-09. Later chapters below are a porting plan, not a claim of
working coverage. See [running instructions](odin_port/README.md), the
[compiler verification](odin_port/verification-2026-09.md), and the
[code and plan audit](odin_port/audit-2026-09.md). Open findings and the CodeRabbit
review assessment are tracked in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## 1. How to read the current ports

Open the matching Swift page beside the chapter's `main.odin`. Follow the same
sequence: create the device/view, make or import a Model I/O mesh, convert it to
MTKMesh, compile the shaders, build the pipeline, encode the draw, and present.
In Odin, `renderer_init` contains setup and `draw` contains command encoding.
`main` supplies the native window that replaces PlaygroundSupport's live view.

| Odin variant | Swift reference | Expected output |
|---|---|---|
| `01-hello-metal` | [Chapter 1 final](01-hello-metal/projects/final/Chapter1.playground/Contents.swift) | Solid red sphere silhouette |
| `01-hello-metal -define:CHALLENGE=true` | [Chapter 1 challenge](01-hello-metal/projects/challenge/Chapter1.playground/Contents.swift) | Tall green ellipse |
| `02-3d-models -define:EXPORT_CONE=true` | [Chapter 2, page 1](<02-3d-models/projects/final/Chapter2.playground/Pages/1 Render and Export 3D Model.xcplaygroundpage/Contents.swift>) | Wireframe cone; exports `generatedCone.usda` |
| `02-3d-models` | [Chapter 2, page 2](<02-3d-models/projects/final/Chapter2.playground/Pages/2 Import Train.xcplaygroundpage/Contents.swift>) | Wireframe train |
| `02-3d-models -define:CHALLENGE=true` | [Chapter 2 challenge](<02-3d-models/projects/challenge/Chapter2.playground/Pages/Import Mushroom.xcplaygroundpage/Contents.swift>) | Wireframe mushroom |

For chapter 2, start with the export variant to follow page order, even though
the default command imports the train. The export overwrites the file of that
name in `odin_port/`; the Swift playground writes to its shared-data directory.

### Deliberate differences to notice

- Swift's playground submits one frame. The native AppKit/MTKView shell redraws
  through a delegate so the window continues to display correctly. This is
  platform support, not an additional rendering lesson.
- Compile-time `CHALLENGE` / `EXPORT_CONE` settings select the corresponding book
  pages. They are mutually exclusive in chapter 2.
- Odin spells Metal types without their Objective-C prefixes: `MTL.Device`,
  `MTL.RenderPipelineDescriptor`, and `.Triangle`. A call such as
  `device->newCommandQueue()` corresponds to Swift's `device.makeCommandQueue()`.
- Chapter 2 requests tightly packed, 12-byte position vertices instead of Swift's
  16-byte `SIMD3<Float>` stride. This is valid because the vertex descriptor and
  imported data agree; the vertex shader fetches `.Float3` through `[[stage_in]]`.
  It is not a license to use 12-byte `float3` fields in GPU-shared structs.
- Both imports use the first MDLMesh, just like the Swift pages; chapter 2 draws
  every submesh of that mesh. This is not yet a scene-hierarchy loader.
- The cone branch also draws every submesh, whereas its Swift page selects the
  first. The supplied generated cone renders equivalently. Keep this distinction
  visible if the geometry changes.
- The pipeline uses the view's pixel format instead of repeating `.bgra8Unorm`.
  The default view format matches the Swift example.

## 2. Framework strategy

Keep the book's Apple-framework pipeline. Narrow bindings let the reader compare
an Odin call with the Swift call without first learning a replacement engine.
The earlier SIMD calling-convention blocker was fixed in dev-2026-08
([issue #7010](https://github.com/odin-lang/Odin/issues/7010),
[PR #7015](https://github.com/odin-lang/Odin/pull/7015)); a clang shim and USDZ-to-glTF
conversion are no longer required.

| Book dependency | Odin approach | Status |
|---|---|---|
| Metal | `vendor:darwin/Metal` | Current draw/pipeline APIs tested; later APIs need validation when introduced |
| MTKView | `vendor:darwin/MetalKit` | Working delegate bridge, with the ownership caveat in §3 |
| Model I/O and MTKMesh | `common:modelio` | Narrow bindings for spheres, cones, vertex descriptors, asset import/export, and submeshes |
| PlaygroundSupport / SwiftUI shell | Native AppKit through `core:sys/darwin/Foundation` | Single-window shell implemented; keep later book UI controls recognizable |
| MathLibrary / simd | `core:math/linalg` plus book-convention helpers | Translation guide in §5; not yet used by chapters 1–2 |
| MTKTextureLoader | Add the selectors/options the texture chapter needs | Planned; preserve the book's texture origin, sRGB, and mipmap choices |
| GameController / notifications | Narrow keyboard/mouse, notification, and block bindings | Planned for chapter 9; camera behavior stays in the chapter |
| Model I/O skeletal data | Extend bindings for transforms, skeletons, and animation arrays | Planned for chapters 23–24; preserve the USD assets and book's sampling logic |
| MetalPerformanceShaders | Bind the used classes | First needed by chapter 19's `MPSImageSobel`; more in chapter 29 |
| MetalFX | Bind the scaler APIs used in chapter 30, Profiling | Planned |

SDL, glTF/cgltf, stb_image, custom primitive generators, and replacement compute
kernels remain possible experiments. They change what the reader must compare,
so they are not the default implementation strategy. Do not assume future Odin
framework coverage or promise that switching bindings will be only an import
change; signatures, naming, and ownership need comparison when coverage arrives.

## 3. Odin and Metal differences that matter

### Ownership and callbacks

Odin does not provide Swift ARC. An owned Objective-C result (`alloc`/`init`,
`new`, `copy`, or an explicitly retained reference) needs a matching release when
its lifetime ends. A borrowed mesh buffer is valid only while its owner remains
alive. NSError results and many convenience-method results are autoreleased.
Keep setup and per-frame autorelease pools; they do not release owned objects
or free Odin dynamic arrays and allocator memory.

The current samples store renderer and application owners explicitly.
`renderer_destroy` releases the mesh, queue, and pipeline and resets borrowed
references. Chapter 2 iterates the owned mesh's submeshes instead of copying them
into an Odin array. Stop drawing before destroying or reinitializing a renderer.
Default Metal command buffers retain encoded resources until GPU completion.

`app_shutdown` pauses/detaches the view and releases the renderer and shell from
`applicationWillTerminate`, including last-window close. The window disables
release-on-close to keep its release under this explicit owner. Do not rely only
on `defer` after `app->run()`: `terminate:` can exit without returning through
Odin's `main`. The cleanup is idempotent and also runs if the run loop returns.

MTKView holds its delegate weakly. Odin's vendor bridge wraps the Odin delegate
in an autoreleased `NSValue`; retain that wrapper across the setup-pool drain.
During teardown, detach the Objective-C delegate before releasing its
wrapper or renderer. `View_setDelegate(nil)` still creates a wrapper in the
current vendor implementation; detaching requires sending a nil Objective-C
`setDelegate:` argument directly.

Foreign callbacks are `proc "c"`. Restore an Odin context before calling
context-dependent assertions or allocation/formatting helpers. The draw callbacks
establish a default context. The Foundation application-delegate helper restores
the context supplied at registration for its Odin callbacks.

Odin's `when` does not create a new scope. Chapter 2's branch-local `defer` calls
therefore run at the end of `renderer_init`, after MTKMesh conversion. Replacing
`when` with a runtime `if` would change those lifetimes and needs a fresh review.

Use `OBJC_DEBUG_MISSING_POOLS=YES` to investigate pool ownership, but inspect the
warning's stack before attributing it to the port or dismissing it as system
noise. It does not detect all retained-object or Odin-allocator leaks.

### Vertex data, GPU structs, and foreign ABI are different layouts

On the tested arm64 compiler:

| Type | Odin size / alignment | Swift/Metal size or stride / alignment |
|---|---|---|
| `[3]f32` vs `float3` | 12 / 4 | 16 / 16 |
| `[4]f32` vs `float4` | 16 / 4 | 16 / 16 |
| `matrix[3,3]f32` vs `float3x3` | 36 / 4 | 48 / 16 |
| `matrix[4,4]f32` vs `float4x4` | 64 / 4 | 64 / 16 |

For a shared normal matrix, upload three padded four-float columns, not a raw
36-byte Odin matrix. For all `Common.h` translations, verify each field offset,
field alignment, total size, and array stride. Merely aligning the outer struct
to 16 bytes does not fix misaligned members inside it. Keep ordinary packed
vectors/matrices for CPU math and introduce explicit upload representations at
the chapter that first shares a struct with a shader.

A vertex descriptor can describe packed 12-byte position data, as chapter 2 does.
That descriptor governs vertex fetching; `constant`/`device` buffer structs and
Objective-C methods taking SIMD values by value have different requirements.
The binding's `#simd[4]f32` is the tested ABI representation for Apple's padded
`vector_float3`; it is not the chapter's position-buffer element type.

### Math and draw behavior

The book uses left-handed view/projection conventions and Metal depth 0..1.
The stock linalg perspective/orthographic helpers use a different depth mapping;
a `flip_z_axis` option alone is not a substitute for the book's constructors.
Keep Euler rotation order and the chapter's transformation chain visible.

Use the MTKMeshBuffer's actual vertex and index offsets when encoding draws.
The current demos preserve both offsets, including for shared-buffer
suballocations, and check command queue, command buffer, and encoder creation
as Swift does. A temporarily unavailable drawable in a continuous MTKView
callback should skip that frame.

Shaders compile at runtime in chapters 1–2. Later chapters may load `.metal`
source or build a `.metallib`, but paths, entry points, defines, and `Common.h`
includes must match the selected book project. Binding presence does not prove
that an advanced shader or feature runs on the current GPU.

## 4. Reading order and implementation priorities

The book's chapter order is the recommended reading order. Writing the examples
is optional. The selected implementation route remains
**1 → 2 → 5 → 7 → 8 → 9 → 10 → 19 → 23–24 → 28 → 29**, with 21, 26, and 30
optional. This prioritizes distinct interop surfaces; it does not mean the
intervening chapters are unnecessary for a reader or already ported.

| Next port | Read/review first | What the port should preserve |
|---|---|---|
| 5: 3D Transformations | 3: Rendering Pipeline; 4: Vertex Function | Renderer structure, vertex inputs, CPU/GPU uniforms, and the book's transform sequence |
| 7: Fragment Function | 6: Coordinate Spaces | View/projection conventions and the interpolation/fragment lesson |
| 8: Textures | The preceding vertex/fragment setup | MTKTextureLoader options, texture coordinates, samplers, and image orientation |
| 9: Navigating a 3D Scene | 5–8 | The book's camera and input behavior, with narrow framework bindings |
| 10: Lighting Fundamentals | 7–9 | Normals, normal-matrix layout, lights, and the lighting equations |
| 19: Tessellation and Terrains | Compare its project with 10; review the intervening render-pass, material, and compute concepts it uses | Tessellation stages, terrain inputs, and MPS Sobel usage |
| 23–24: Animation / Character Animation | Review hierarchy, materials, and transforms in the selected final projects | Model I/O animation data, coordinate spaces, interpolation, and skinning |
| 28: Mesh Shaders | Read the GPU-driven command-encoding chapters 25–27 | Mesh/object pipeline stages and their actual resource requirements |
| 29: Metal Performance Shaders | Review its input/output texture flow | The demonstrated MPS operations and results |

Before each jump, compare the target Swift project's files and shaders with the
last port. List the missing prerequisites in that chapter's README and explain
where the carried-forward code came from. Do not call the catch-up small until
that comparison is done, or move its rendering concepts into `common/` to hide it.

Each implemented chapter should include: links to exact Swift variants; commands
in book-page order; expected output; a short Swift-to-Odin reading map; deliberate
differences; and any current limitations. Starter/final/challenge code should
remain identifiable. Share framework support, while keeping code the book is
actively teaching visible in the chapter package.

## 5. Math cheat sheet: Swift simd / MathLibrary → Odin

### 5.1 Types

| Swift | Odin | Notes |
|---|---|---|
| `float2` / `SIMD2<Float>` | `[2]f32` (`linalg.Vector2f32`) | Odin arrays have full array programming |
| `float3` / `SIMD3<Float>` | `[3]f32` (`linalg.Vector3f32`) | ⚠ 12 bytes in Odin vs 16 in Swift — pad in GPU-shared structs |
| `float4` / `SIMD4<Float>` | `[4]f32` (`linalg.Vector4f32`) | |
| `float3x3` | `matrix[3,3]f32` (`linalg.Matrix3f32`) | CPU math only: 36 bytes here; Metal/Swift use 48 bytes with padded columns |
| `float4x4` | `matrix[4,4]f32` (`linalg.Matrix4f32`) | Same 64-byte column data; Odin alignment is 4, Metal/Swift alignment is 16 |
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
| `matrix_identity_float4x4` / `.identity` | `linalg.MATRIX4F32_IDENTITY` (or `(matrix[4,4]f32)(1)`) |
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
| TRS with a quaternion rotation | `linalg.matrix4_from_trs_f32(t, q, s)`; the book's early `Transform.rotation` is Euler angles, so keep its explicit translation × rotation × scale chain |

### 5.4 Reference math helpers for later chapters

The three camera constructors below preserve the book's conventions; the two
Euler helpers make its multiplication order explicit. They are reference code,
not an implemented shared package yet. Introduce them alongside chapters 5–6,
then share them once the reader has seen their purpose.

The formulas correspond to the book's `MathLibrary.swift`. Odin matrix literals
are written row by row, whereas Swift's initializer takes columns. Numerical
comparison with the chapter 10 Swift helpers passed for both perspective/view
handedness options, orthographic projection, and both Euler orders on dev-2026-09.
This checks matrix values; GPU struct padding must still follow §3.

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

Use the table to translate operations as they appear in the chapter. Similar
procedure names do not establish matching handedness, depth range, Euler order,
or foreign ABI. Prefer the book's vocabulary to changing naming conventions
halfway through a chapter.

## 6. Verification when adding a chapter

1. Identify the exact Swift variant, assets, shaders, and expected output.
2. Run `just check` for all implemented variants
   (`odin check -strict-style -warnings-as-errors`), then use `just run <chapter>`
   for the selected example. Compile runnable documentation snippets, too.
3. Run with Metal API and shader validation, inspect the image and interactions,
   and exercise normal close behavior. An unavailable sandbox GPU is not a pass.
4. Check new ownership boundaries: pool drains, borrowed results, callbacks,
   repeated loads, and teardown. Run affected variants with
   `just sanitize <chapter> [flags...]` (`-debug -sanitize:address`) and Odin test
   packages with `just test-sanitize <package>`. Use zombie diagnostics for
   suspicious Objective-C lifetimes; sanitizer success and visually correct
   output alone do not establish balanced ownership.
5. Check every new CPU/GPU shared layout. Compare math with the Swift reference
   and test near/far depth and other boundary conditions.
6. Record what was tested, the compiler/platform, and any intentional differences.
   Only then mark the chapter implemented.

The chapter-3 rendering-pipeline example, when ported, should follow the book's
MTKView/Renderer structure. The earlier standalone SDL triangle sketch has been
removed from this reading plan because it introduced a second application
architecture before the reader needed one.
