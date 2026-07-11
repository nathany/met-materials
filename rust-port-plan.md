# Porting *Metal by Tutorials* (5th ed.) to Rust

A feasibility assessment and working plan for working through the book in Rust, using
[objc2](https://github.com/madsmtm/objc2) framework crates for Apple's APIs and
[glam](https://github.com/bitshifter/glam-rs) for math. Based on a survey of this repo
(31 chapters, 72 Xcode projects), the objc2 checkout + its `objc2-generated` bindings,
and the glam checkout (July 2026; objc2 0.6.x tracking the **Xcode 26.5 SDK**).

**Verdict: the most complete binding story available.** Every framework the book touches
has a generated, SDK-current objc2 crate — including Model I/O, so the book's USDZ asset
pipeline and skeletal-animation chapters work as written. objc2 even ships an
`examples/metal/` suite (triangle with MTKView+delegates, texture, argument buffers,
bindless, mesh shaders, MPS, ray tracing) whose triangle is structured exactly like the
book's `Renderer`/`MetalView` split. The work is not finding APIs — it's managing the
`unsafe` surface, which is measurable and concentrated (see §3).

## 1. Framework coverage

Every book dependency → an objc2 framework crate (all generated from Xcode 26.5 headers):

| Book dependency | Crate | Notes |
|---|---|---|
| Metal | `objc2-metal` | Complete, incl. ICBs (ch. 26), mesh pipelines (ch. 28), ray tracing, **Metal 4** (31 `MTL4*` files, beyond the book's needs) |
| MetalKit | `objc2-metal-kit` | `MTKView`, `MTKViewDelegate`, `MTKTextureLoader`, `MTKMesh`/`MTKModel` — the full loader stack the book uses |
| Model I/O | `objc2-model-io` | `MDLAsset`, `MDLMesh`, `MDLVertexDescriptor`, `MDLAnimation`/skeletal types (ch. 23–24), `MDLVoxelArray`, materials — **USDZ pipeline survives intact** |
| MetalPerformanceShaders (ch. 29) | `objc2-metal-performance-shaders` | Sobel/blur/threshold/matrix-mul all present; objc2 has an MPS example |
| MetalFX (ch. 30) | `objc2-metal-fx` | Spatial/temporal scalers |
| GameController | `objc2-game-controller` | `GCKeyboard`, `GCMouse` — the book's input layer ports 1:1 |
| AppKit (window shell) | `objc2-app-kit` | Replaces the SwiftUI wrapper; `define_class!` gives you `NSApplicationDelegate` + `MTKViewDelegate` in the book's exact shape |
| QuartzCore / CoreGraphics | `objc2-quartz-core`, `objc2-core-graphics` | `CAMetalLayer`/`CAMetalDrawable` if you skip MTKView |
| simd + MathLibrary.swift | `glam` | §5 cheat sheet |

Swift-only pieces (SwiftUI, Observation, PlaygroundSupport) are the app shell only and
are replaced by the AppKit delegate structure above — the objc2 triangle example is the
template.

Suggested `Cargo.toml` starting set:

```toml
[dependencies]
objc2 = "0.6"
objc2-foundation = "0.3"
objc2-app-kit = "0.3"
objc2-metal = "0.3"
objc2-metal-kit = "0.3"
objc2-quartz-core = "0.3"
objc2-model-io = "0.3"
objc2-game-controller = "0.3"
glam = { version = "0.30", features = ["bytemuck"] }
bytemuck = { version = "1", features = ["derive"] }
```

(Framework crates use per-class cargo features; enable what each chapter needs or
`features = ["all"]` while learning. Add `objc2-metal-performance-shaders` and
`objc2-metal-fx` for ch. 29–30.)

## 2. The objc2 model in one paragraph

Obj-C classes are opaque Rust types; protocols (`MTLDevice`, `MTLBuffer`, …) appear as
`ProtocolObject<dyn MTLDevice>`. Ownership is inferred from Cocoa method families —
anything returning an object gives you `Retained<T>`, which releases on drop: **no manual
retain/release, no autorelease-pool discipline to get wrong** (pools still exist via
`autoreleasepool(|| …)` for keeping frame memory flat, but leaks-by-omission aren't a bug
class the way they are with manual bindings). UI types are `MainThreadOnly`; a
`MainThreadMarker` proves you're on the main thread at compile time. `define_class!`
declares real Obj-C subclasses in Rust (delegates, view controllers) with typed ivars.
`msg_send!` remains as the escape hatch for anything unbound. Selector names map
mechanically: `newLibraryWithSource:options:error:` → `newLibraryWithSource_options_error`
(the `_error` suffix drops and becomes `Result`).

## 3. The `unsafe` surface — measured, and where to put the boundary

Counted across the generated bindings (Xcode 26.5 snapshot):

| Framework | safe fns | unsafe fns | character |
|---|---|---|---|
| Metal | 1,571 | 228 (~13%) | curated; unsafe = raw pointers & unvalidated GPU state |
| MetalKit | 83 | 16 | curated |
| **Model I/O** | **0** | **667 (100%)** | **never audited** — blanket `unsafe`, most calls are actually benign |

What that means in practice, from reading the generated code and objc2's own triangle:

**Mostly safe already:** device/queue/pipeline creation (`newCommandQueue`,
`newLibraryWithSource_options_error` → `Result`, `newRenderPipelineStateWithDescriptor_error`,
`setVertexFunction`), command buffer lifecycle (`commandBuffer`,
`renderCommandEncoderWithDescriptor`, `presentDrawable`, `commit`), render-pass load/store
config, `MTKView` property surface.

**The recurring unsafe hot spots** (all in the per-frame path):
- `colorAttachments().objectAtIndexedSubscript(0)` — unchecked index
- `setVertexBytes_length_atIndex` / `setVertexBuffer_offset_atIndex`,
  `setFragment*` — binding indices and lengths are promises to the GPU
- `drawPrimitives…` / `drawIndexedPrimitives…`
- `MTLBuffer::contents()` returns `NonNull<c_void>` (safe to call, unsafe to use)
- `replaceRegion_…_withBytes_bytesPerRow` — raw byte pointer
- `NSWindow`/view `init…` variants on the AppKit side
- everything in Model I/O (unaudited rather than dangerous — e.g.
  `MDLAsset::initWithURL` is `unsafe` only because nobody has marked it)

**Recommended boundary — mirror the book's `Utility/` folder as the unsafe boundary.**
The book already isolates its plumbing in per-project utility files; make those the safe
wrappers, and per-chapter "game" code stays 100% safe Rust:

- `common/gpu.rs` — pipeline/depth-state builders, shader compile. Nearly all safe
  already; wraps the two attachment-subscript `unsafe`s.
- `common/frame.rs` — a thin typed encoder wrapper: `bind_vertex<T: Pod>(&self, index,
  &T)`, `bind_vertex_buffer(&self, index, &BufferSlice)`, `draw(...)`. Internally
  `bytemuck::bytes_of` + `setVertexBytes…`; the `unsafe` block documents the invariant
  (length = size_of val, index matches the MSL `[[buffer(n)]]`). This captures ~80% of
  the recurring unsafe in one file, and the index-matching invariant is *real* — a safe
  wrapper can't check it against the shader, only centralize it.
- `common/buffer.rs` — `Buffer<T>` newtype over `Retained<ProtocolObject<dyn MTLBuffer>>`
  storing a length; `write(&[T])`/`as_slice()` via `contents()` + bytemuck, upholding
  bounds + `StorageModeShared` in one audited place.
- `common/assets.rs` — the Model I/O → `MTKMesh` pipeline. All calls unsafe; keep every
  one in this file with a safe `Model::load(url) -> Model` API. Same for
  `common/texture.rs` (`MTKTextureLoader`).

Set `#![deny(unsafe_op_in_unsafe_fn)]` (objc2's examples do) and add a one-line
`// SAFETY:` on each block. Expect on the order of **a few dozen unsafe blocks total in
`common/`, and near-zero in chapter code** — don't chase zero; the unsafe that remains
encodes genuine GPU-contract invariants Rust can't see (bind indices vs. MSL, buffer
lifetimes across in-flight frames, `.xcassets`-less resource paths).

One Rust-specific invariant the book's Swift never surfaces: with a triple-buffered
uniform ring (ch. 30 style), a `&mut` view into `contents()` while the GPU may read it is
UB-adjacent — model it as raw writes (`ptr::copy_nonoverlapping`) gated by the book's
semaphore pattern (`DispatchSemaphore` → `objc2-dispatch`/`dispatch2` crate, or a
`std::sync` equivalent).

## 4. App shell, input, shaders

- **Windowing:** `define_class!` versions of `NSApplicationDelegate` + `MTKViewDelegate`,
  `MTKView::initWithFrame_device` — objc2's `examples/metal/triangle/main.rs` is a
  ~100-line working template of exactly the book's ch. 1–3 structure. (A `winit`
  + `raw-window-handle` + `CAMetalLayer` shell is the more idiomatic-Rust alternative,
  but MTKView keeps you closest to the book and its `draw(in:)`/resize callbacks.)
- **Input:** `objc2-game-controller` has `GCKeyboard`/`GCMouse`; the book's
  `InputController.swift` ports nearly line-for-line.
- **Shaders:** MSL files port unchanged. No Xcode bundle: either compile at runtime
  (`newLibraryWithSource_options_error(ns_string!(include_str!("Shaders.metal")), None)`
  — the objc2 examples' approach, `Result` and all) or have `build.rs` shell out to
  `xcrun metal`/`metallib` and load `newLibraryWithFile`. `include_str!` is the low-
  friction default while working through chapters.
- **Assets:** load USDZ by file path via `MDLAsset`; textures via `MTKTextureLoader`
  (`newTextureWithContentsOfURL_options_error`). The `.xcassets` cube-texture sets are an
  Xcode build artifact — supply the 6 faces as plain PNGs (or one strip) and build the
  cube texture through the loader/blit path once in `common/texture.rs`.
- **Debugging:** `MTL_DEBUG_LAYER=1`, `MTL_SHADER_VALIDATION=1`; GPU capture by attaching
  Xcode to the Rust binary or `MTLCaptureManager` (bound, safe).

## 5. Math cheat sheet: Swift simd / MathLibrary → glam

glam is a *better* convention match than simd was: **column-major storage** (identical
memory layout to MSL `float4x4` — never transpose) and projection constructors that
target Metal's depth range natively.

### 5.1 Types

| Swift | glam | GPU-shared struct notes |
|---|---|---|
| `float2` | `Vec2` | 8 B, matches MSL `float2` |
| `float3` | `Vec3` (12 B) or `Vec3A` (16 B, SIMD) | MSL `float3` is 16-byte aligned → in `#[repr(C)]` uniform structs use `Vec3A`/`Vec4` or explicit padding; `Vec3` matches MSL `packed_float3` |
| `float4` | `Vec4` | 16 B ✓ |
| `float4x4` | `Mat4` | 64 B, column-major ✓ — bit-identical to MSL |
| `float3x3` | `Mat3` (36 B) or `Mat3A` (48 B) | MSL `float3x3` has padded columns (48 B) → **use `Mat3A` in shared structs** |
| `simd_quatf` | `Quat` | |
| `matrix_double4x4` | `DMat4` → `.as_mat4()` | replaces the book's double→float converters |
| `SIMD4<Double>` | `DVec4` → `.as_vec4()` | |

Enable the `bytemuck` feature and `#[derive(Pod, Zeroable)]` on `#[repr(C)]` uniform
structs mirroring the book's `Common.h` — this is the safe bridge for `setVertexBytes`
and `contents()` writes (§3).

### 5.2 Constants, accessors, operators

| Swift | glam / std |
|---|---|
| `π` / `Float.pi` | `std::f32::consts::PI` |
| `x.degreesToRadians` / `.radiansToDegrees` | `x.to_radians()` / `x.to_degrees()` (std, no library needed) |
| `.identity` / `matrix_identity_float4x4` | `Mat4::IDENTITY` |
| `v.xyz` | `v.truncate()` or `v.xyz()` (`use glam::Vec4Swizzles`) — full swizzle set |
| `m.columns.3` | `m.w_axis` (also `m.col(3)`, `m.x_axis`…) |
| `normalize/dot/cross/length/distance` | methods: `v.normalize()`, `v.dot(w)`, `v.cross(w)`, `v.length()`, `v.distance(w)` |
| `m.inverse`, `m.transpose` | `m.inverse()`, `m.transpose()` |
| `m1 * m2`, `m * v`, component-wise `v1 * v2` | same operators |

### 5.3 MathLibrary.swift → glam, function by function

| MathLibrary (Swift) | glam |
|---|---|
| `float4x4(translation: t)` | `Mat4::from_translation(t)` |
| `float4x4(scaling: s)` (vector) | `Mat4::from_scale(s)` |
| `float4x4(scaling: s)` (uniform) | `Mat4::from_scale(Vec3::splat(s))` |
| `float4x4(rotationX: a)` | `Mat4::from_rotation_x(a)` (same convention — verified against the book's column layout) |
| `float4x4(rotationY: a)` / `rotationZ` | `Mat4::from_rotation_y(a)` / `from_rotation_z(a)` |
| `float4x4(rotation: [x,y,z])` (X·Y·Z) | `Mat4::from_rotation_x(a.x) * Mat4::from_rotation_y(a.y) * Mat4::from_rotation_z(a.z)` — or `Mat4::from_euler(EulerRot::XYZ, a.x, a.y, a.z)` |
| `float4x4(rotationYXZ:)` | `Mat4::from_euler(EulerRot::YXZ, …)` |
| `float4x4(projectionFov: fov, near:, far:, aspect:, lhs: true)` | **`Mat4::perspective_lh(fov, aspect, near, far)`** — LH, `[0,1]` depth: exact match, no hand-rolling |
| same with `lhs: false` | `Mat4::perspective_rh(fov, aspect, near, far)` (`[0,1]` depth) |
| `float4x4(eye:target:up:)` (LH lookAt) | **`Mat4::look_at_lh(eye, target, up)`** — same forward/right conventions (`s = up × f`) |
| `float4x4(orthographic: rect, near:, far:)` | **`Mat4::orthographic_lh(left, right, bottom, top, near, far)`** — `[0,1]` depth (docs: "…that WebGPU/Direct3D/**Metal** expect") |
| `m.upperLeft` | `Mat3::from_mat4(m)` (or `Mat3A::from_mat4`) |
| `float3x3(normalFrom4x4: m)` | `Mat3::from_mat4(m).inverse().transpose()` |
| Transform TRS compose | `Mat4::from_scale_rotation_translation(scale, rotation, translation)` (≡ T·R·S) |
| `simd_quatf.identity` | `Quat::IDENTITY` |
| `simd_quatf(angle:axis:)` | `Quat::from_axis_angle(axis, angle)` (note the flipped arg order) |
| `simd_slerp(q1, q2, t)` | `q1.slerp(q2, t)` |
| `q.act(v)` | `q * v` (or `q.mul_vec3(v)`) |
| `simd_quatf(m)` | `Quat::from_mat4(&m)` / `from_mat3` |
| `float4x4(q)` | `Mat4::from_quat(q)` |

The **entire MathLibrary.swift is subsumed** — unlike the simd version, nothing needs
hand-writing, and the left-handed `[0,1]`-depth constructors mean the book's projection
and shadow-map matrices are one-liners with the correct clip space out of the box.

## 6. Suggested port structure

- Cargo **workspace**: `common/` library crate (the §3 modules: `gpu`, `frame`, `buffer`,
  `assets`, `texture`, plus `camera`, `input`, `transform`) + one small binary crate per
  chapter (`ch01-hello-metal/`, …). Chapters stay as thin as the book's per-project code
  because the safe layer plays the role of the book's `Utility/` folder.
- Assets: point at this repo's `resources/` (USDZ + PNG as-is; no conversion step).
- Chapter difficulty: **1–24 port with full library support** (including animation —
  Model I/O's skeletal types are bound). **25–28** (bindless/ICB/GPU-driven/mesh shaders)
  are bound and objc2 has bindless + mesh-shader examples to crib from. **29–30**
  (MPS/MetalFX) have dedicated crates — the only ecosystem where those chapters need no
  substitution.

## 7. Discoveries from porting chapter 1 (`rust/01-hello-metal/`)

Lessons from the first working port (both playgrounds build and render with
`MTL_DEBUG_LAYER=1` clean):

1. **objc2 skips every method with simd types in its signature** ("simd types are not
   yet possible in methods" in header-translator). That includes *all* of `MDLMesh`'s
   procedural initializers (`initSphereWithExtent:…`, `newBox…`, planes), plus assorted
   Model I/O/GameController surface. The workaround that works on stable Rust:
   cast `objc2::ffi::objc_msgSend` to a function pointer with the exact C signature,
   using `core::arch::aarch64::float32x4_t`/`uint32x2_t` for `vector_float3`/
   `vector_uint2` (NEON register ABI matches). Pattern in
   [`rust/01-hello-metal/src/lib.rs`](rust/01-hello-metal/src/lib.rs) (`sphere_mesh`) and
   [`src/simd.rs`](rust/01-hello-metal/src/simd.rs). Ownership: `MDLMesh::alloc()` →
   `Allocated::as_ptr` + `mem::forget` (init consumes the +1) → `Retained::from_raw`.
   Expect to reuse this for later chapters' procedural primitives; consider promoting it
   into the shared `common` crate when it grows a second caller.

   **Full impact inventory** (book's Swift sources vs. generated bindings — nothing in
   the book is unportable; every gap is Model I/O-shaped and falls into one of three
   helper patterns):

   | Book usage | Where | Gap | Helper pattern |
   |---|---|---|---|
   | `MDLMesh(sphere/plane/box/coneWithExtent:…)` — 51/50/13/2 call sites, most chapters | ch. 1 onward | all four initializers skipped | by-value vectors → NEON-typed `objc_msgSend` (the ch. 1 pattern; ~15 lines per initializer, shared module) |
   | `asset.boundingBox`, `.maxBounds`/`.minBounds` | ch. 23–25, 29, 30 | `MDLAxisAlignedBoundingBox` struct not generated at all (simd fields) | vector-aggregate return → msgSend typed as returning `#[repr(C)] (float32x4_t, float32x4_t)` (ARM64 returns it in v0/v1); or compute bounds from vertex data (~20 lines, honest alternate) |
   | `.float4x4Array` (`MDLMatrix4x4Array`), `.float3Array`, `.floatQuaternionArray` (skeleton + joint animation) | ch. 23–24 | pointer-to-simd getters (`getFloat4x4Array:maxCount:` etc.) skipped; the *classes* are generated | easiest of the three: pointer args are plain pointers — msgSend typed with `*mut Mat4` / `*mut Vec4` writes **directly into glam types** (matching column-major layout) |

   **Will objc2 grow simd support?** Yes — clearly in progress upstream: PR #584
   ("support-simd") merged, the encoding-check fix is in the unreleased changelog, an
   `unstable-simd` test feature exists, and header-translator already maps
   `vector_float3` → `core::simd::Simd<f32, 3>`. Method emission is blocked on Rust
   stabilizing SIMD-in-FFI (rust-lang/rust#63068) / portable SIMD, so expect it to
   arrive nightly-gated first. The helpers are written to be deleted: each one is the
   same selector the generated method will eventually expose, so call sites keep their
   book-shaped names and only the helper module shrinks when upstream catches up.
2. **`msg_send!` + `Encoding::None` does not work on released objc2 (≤ 0.6.4)** for simd
   arguments: the Obj-C runtime records an *empty* encoding for vector parameters, and
   the debug-build verifier rejects the call ("expected argument at index 0 to have type
   code 'B', but found ''"). A fix exists upstream but is unreleased. Alternatives to the
   raw-msgSend pattern: the `objc2/disable-encoding-assertions` feature (turns off a
   safety net globally — not worth it) or pinning objc2 git (fights the published
   framework-crate versions). Revisit when objc2 > 0.6.4 ships.
3. **`final` is a reserved Rust keyword** — binaries can't be named `final`. Convention:
   `chNN-final` / `chNN-challenge`.
4. Small API-shape notes: `alloc()` on non-UI classes needs `use objc2::AnyThread`;
   upcast a `CAMetalDrawable` for `presentDrawable` with
   `ProtocolObject::from_ref(&*drawable)`; `NSArray` indexing is `.objectAtIndex(n)`
   (panics in-runtime on out-of-bounds); set `window.setReleasedWhenClosed(false)` when
   holding the `NSWindow` in a `Retained` ivar.
5. The `#[improper_ctypes_definitions]` lint fires on SIMD types in `extern fn` types —
   conservative; `#[allow]` it where the aarch64 NEON ABI is what you want.
6. Playground chapters (1–2) have no run loop of their own; wrapping them in the
   AppKit-delegate shell (drawing per-frame via `MTKViewDelegate`) matches what the
   book's own projects do from chapter 3 onward, so the early ports double as the
   template for later chapters.

## 8. Milestones / verification

1. **Prove the toolchain**: build and run objc2's own example from your checkout —
   `cargo run --package metal-examples --bin triangle` (or from `examples/metal/`) — a
   rotating triangle in an MTKView-backed window.
2. **Own triangle**: recreate it in the workspace with `common/` seams in place
   (`include_str!` shader, `frame.rs` wrapper). Run with `MTL_DEBUG_LAYER=1`.
3. **Asset pipeline**: `MDLAsset` → `MTKMesh` load of `train.usdz` from this repo,
   rendered with depth — proves the Model I/O route and the §3 `assets.rs` boundary.
4. **Camera + input**: glam view/projection (§5) + `GCKeyboard`/`GCMouse` — end of
   part I equivalence; then proceed chapter order.
