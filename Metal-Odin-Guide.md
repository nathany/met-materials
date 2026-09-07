# *Metal by Tutorials* (5th ed.) Supplementary Guide for Odin

Use this guide alongside the book when writing its examples in Odin. The book
provides the rendering concepts, algorithms, and Metal shaders; this supplement
explains how Swift types, Apple framework calls, memory management, and math
translate to Odin. Follow the book's chapter order and keep the corresponding
Swift project nearby when comparing behavior.

Use **Odin dev-2026-09 or newer**, macOS with a Metal-capable GPU, and Xcode's
command-line tools and SDKs. Later chapters also depend on the Metal features
supported by your GPU and macOS version.

The [Odin reference implementation](odin_port/README.md) is available to inspect
or run as a companion. Its README lists implemented examples and commands;
you can also write your own implementations using this guide.

## 1. Translating the Swift examples

The rendering sequence stays the same: create a device and view, prepare mesh
buffers, compile shaders, create a pipeline, encode a draw, and present it.
Metal Shading Language stays Metal Shading Language; Odin replaces the Swift
host code.

| Swift spelling or pattern | Odin equivalent |
|---|---|
| `MTLDevice`, `MTLRenderPipelineDescriptor` | `MTL.Device`, `MTL.RenderPipelineDescriptor` with `MTL` as the import alias |
| `device.makeCommandQueue()` | `device->newCommandQueue()` |
| `.triangle` | `.Triangle` for the Metal primitive type |
| Renderer class with methods | A renderer struct and procedures operating on its state |
| ARC-managed object references | Explicit owners and matching releases; see §3 |
| `guard let` / forced unwrap | Check the returned pointer or error before using it |

### Playgrounds and the application shell

Chapters 1–2 display an MTKView through PlaygroundSupport. In an Odin application,
AppKit supplies the window and event loop, and an MTKView delegate supplies the
draw callback. This resembles the standalone application structure introduced
later in the book. Continuous drawing keeps the native window refreshed even
when the playground example submits only one frame.

When the book uses SwiftUI controls, preserve what the controls do in your
application shell. Keep input and camera behavior recognizable as those lessons
arrive; the choice of UI language need not change the rendering algorithm.

### Model I/O and assets

Model I/O can generate the chapter 1 sphere, generate and export the chapter 2
cone, and load the book's original USDZ assets. MTKMesh converts Model I/O mesh
data into buffers Metal can draw. Use the same geometry and assets while learning
the book's rendering pipeline.

Chapter 2's imported pages select the first MDLMesh and draw its submeshes. A
submesh describes an indexed draw within that mesh; this is separate from loading
an entire scene hierarchy. When following the export page, choose an output path
your application can write to in place of the playground's shared-data directory.

## 2. Apple frameworks from Odin

Odin's Darwin packages expose Objective-C calls through types and procedures.
For APIs without supplied bindings, small declarations using `@(objc_class)` and
`intrinsics.objc_send` let you call the same Apple frameworks used by Swift.
The reference implementation's [Model I/O bindings](odin_port/common/modelio/modelio.odin)
show this pattern for mesh creation and loading.

The following describes the dev-2026-09 starting point. Check your installed
compiler's packages when using a newer release.

| Book dependency | Odin package or binding work |
|---|---|
| Metal | `vendor:darwin/Metal` provides the core device, buffer, pipeline, and command APIs |
| MTKView | `vendor:darwin/MetalKit`; see the delegate ownership details in §3 |
| AppKit application and window | `core:sys/darwin/Foundation` |
| Model I/O and MTKMesh | Additional bindings for mesh creation, vertex descriptors, asset loading/export, and submeshes |
| MathLibrary / simd | `core:math/linalg` plus the book's projection and view conventions; see §5 |
| MTKTextureLoader | Additional selectors and options for chapter 8's texture loading |
| GameController and notifications | Bind the keyboard/mouse APIs and callbacks used by chapter 9 |
| Skeletal animation | Extend Model I/O coverage for transforms, skeletons, and animation arrays in chapters 23–24 |
| MetalPerformanceShaders | Bind the used classes, including chapter 19's `MPSImageSobel` and chapter 29's operations |
| MetalFX | Bind the scaler APIs used in chapter 30 |

We hope Odin 2027 will provide more of these framework bindings. As equivalent
APIs become available, prefer the supplied packages after comparing their
signatures, ownership rules, and behavior with the declarations you are using.
The Metal concepts and book examples remain the same across that transition.

## 3. Odin and Metal differences that matter

### Ownership and callbacks

Odin does not provide Swift ARC. An owned Objective-C result (`alloc`/`init`,
`new`, `copy`, or an explicitly retained reference) needs a matching release when
its lifetime ends. A borrowed mesh buffer is valid only while its owner remains
alive. NSError results and many convenience-method results are autoreleased.
Keep autorelease pools around setup and each frame; they do not release owned
objects or free Odin dynamic arrays and allocator memory.

Store the mesh owner alongside any borrowed buffers needed for drawing. Pair
renderer initialization with destruction, and stop callbacks before destroying
state they use. Default Metal command buffers retain encoded resources until
GPU work completes, so CPU ownership and GPU completion are separate lifetimes.

AppKit's `applicationWillTerminate` callback can handle cleanup for Quit and
last-window close. `terminate:` may exit without returning from `app->run()`, so
cleanup deferred only after that call is insufficient. Choose who releases the
window: `setReleasedWhenClosed(false)` lets an explicit application owner release
it during shutdown.

MTKView holds its delegate weakly. The dev-2026-09 Odin bridge wraps the Odin
delegate in an autoreleased `NSValue`; retain that wrapper while installed.
Pause the view and detach its Objective-C delegate before releasing the wrapper
or renderer. In this binding, `View_setDelegate(nil)` still creates a wrapper;
send a nil Objective-C `setDelegate:` argument directly to detach it.

Foreign callbacks are `proc "c"`. Establish an Odin context before calling
context-dependent assertions, formatting, or allocation helpers. Foundation's
application-delegate helper restores the context supplied at registration.

Odin's compile-time `when` does not introduce a scope: a `defer` within its chosen
branch runs at the end of the enclosing scope. A runtime `if` does introduce a
scope, so replacing one with the other can change resource lifetimes.

### Vertex data, GPU structs, and foreign ABI are different layouts

For ordinary Odin arrays and matrices on macOS arm64:

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

A vertex descriptor can describe packed 12-byte positions for position-only
meshes.
That descriptor governs vertex fetching; `constant`/`device` buffer structs and
Objective-C methods taking SIMD values by value have different requirements.
For Objective-C calls, `#simd[4]f32` represents the ABI layout of Apple's padded
`vector_float3`; it is not the chapter's position-buffer element type.

### Math and draw behavior

The book uses left-handed view/projection conventions and Metal depth 0..1.
The stock linalg perspective/orthographic helpers use a different depth mapping;
a `flip_z_axis` option alone is not a substitute for the book's constructors.
Keep Euler rotation order and the chapter's transformation chain visible.

Use the MTKMeshBuffer's actual vertex and index offsets when encoding draws.
Several mesh buffers can share one Metal allocation. Check command queue,
command buffer, and encoder creation, as the Swift examples do. A temporarily
unavailable drawable in a continuous MTKView callback should skip that frame.

Shaders compile at runtime in chapters 1–2. Later chapters may load `.metal`
source or build a `.metallib`, but paths, entry points, defines, and `Common.h`
includes must match the selected book project. Binding presence does not prove
that an advanced shader or feature runs on the current GPU.

## 4. What to watch for as you read

Read the intervening chapters even when you focus your Odin implementation on
selected examples. Later Swift projects carry forward earlier rendering and
resource-management concepts.

| Chapters | Odin-specific points to keep alongside the lesson |
|---|---|
| 1–2: Hello, Metal! / 3D Models | Native application shell, Model I/O calls, ownership, and mesh-buffer offsets |
| 3–4: Rendering Pipeline / Vertex Function | Renderer state, pipeline descriptors, vertex inputs, and shader entry points |
| 5–7: Transformations through Fragment Function | Matrix multiplication order, coordinate conventions, uniform layout, and interpolation |
| 8: Textures | Texture origin, sRGB choices, mipmaps, and sampler settings when binding MTKTextureLoader |
| 9: Navigating a 3D Scene | Keyboard/mouse callbacks, camera state, and the book's input behavior |
| 10: Lighting Fundamentals | Normals, inverse-transpose transforms, and padded normal-matrix uploads |
| 19: Tessellation and Terrains | Tessellation stages, terrain inputs, and MPS Sobel filtering; review the render-pass, material, and compute concepts used by its project |
| 23–24: Animation / Character Animation | Model hierarchy, animation sampling, interpolation, coordinate spaces, and skinning |
| 25–28: GPU-driven rendering through Mesh Shaders | Command encoding, resource lifetime/synchronization, and the GPU's supported pipeline stages |
| 29–30: Metal Performance Shaders / Profiling | Framework bindings, input/output texture flow, hardware support, and measurements |

When comparing a result, check more than whether geometry appears: camera
orientation, depth ordering, texture orientation, lighting, and controls should
follow the selected Swift example. For small math helpers, the boundary checks
in §5 can reveal convention differences before they reach a shader.

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
| `float4x4(rotationX: a)` | `linalg.matrix4_rotate_f32(a, {1, 0, 0})` — same axis-rotation convention |
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
Euler helpers make its multiplication order explicit. Use them alongside
the coordinate-space discussion in chapters 5–6, comparing each operation with
the corresponding `MathLibrary.swift` helper.

The formulas correspond to the book's `MathLibrary.swift`. Odin matrix literals
are written row by row, whereas Swift's initializer takes columns. For a projection
check, the near and far planes should map to depth 0 and 1; a view matrix should
map the camera position to the origin. GPU struct padding still follows §3.

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
