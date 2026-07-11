//! FFI-compatible simd vector values for Objective-C methods that take
//! `vector_float3` / `vector_uint2` parameters.
//!
//! objc2's generated bindings skip any method whose signature contains a
//! simd type ("simd types are not yet possible in methods"), which includes
//! all of `MDLMesh`'s procedural initializers. On Apple silicon those
//! parameters are passed in NEON vector registers, and `core::arch`'s
//! `float32x4_t`/`uint32x2_t` have exactly that ABI — so such selectors can
//! be called through a suitably-typed `objc_msgSend` function pointer (see
//! `sphere_mesh` in lib.rs).
//!
//! Note: `msg_send!` can't be used for these until objc2's encoding
//! verification understands simd arguments (fixed upstream after 0.6.4) —
//! the Objective-C runtime records an *empty* type encoding for vector
//! parameters, which the released verifier rejects in debug builds.

// Apple Silicon only: on x86_64 these would be __m128/SSE types with a
// different ABI to audit. Not worth supporting for a learning port.
#[cfg(not(target_arch = "aarch64"))]
compile_error!("the simd-selector workaround is written for Apple silicon (aarch64) only");

use core::arch::aarch64::{float32x4_t, uint32x2_t};

/// A `vector_float3`: three floats in a 16-byte vector register.
pub fn vector_float3(v: [f32; 3]) -> float32x4_t {
    // SAFETY: [f32; 4] and float32x4_t have the same size (16 bytes) and bit
    // layout (array order = vector lane order); any bit pattern is a valid
    // f32 lane.
    unsafe { core::mem::transmute::<[f32; 4], float32x4_t>([v[0], v[1], v[2], 0.0]) }
}

/// A `vector_uint2`: two u32s in an 8-byte vector register.
pub fn vector_uint2(v: [u32; 2]) -> uint32x2_t {
    // SAFETY: same as `vector_float3` — matching size (8 bytes) and lane
    // layout, and any bit pattern is a valid u32 lane.
    unsafe { core::mem::transmute::<[u32; 2], uint32x2_t>(v) }
}
