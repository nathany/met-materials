// Clang-compiled shim for MDLMesh's sphere initializer.
//
// Odin cannot call this selector directly: its signature contains simd
// vector parameters (vector_float3, vector_uint2), and Odin's #simd types
// do not follow the C vector calling convention (passed in general-purpose
// registers instead of SIMD registers — see Metal-odin-port-plan.md §3.10).
// This shim exposes scalars only, which both compilers agree on.
//
// Compiled WITHOUT ARC: returns a +1 (owned) object; the Odin caller is
// responsible for release().
#import <MetalKit/MetalKit.h>
#import <ModelIO/ModelIO.h>

MDLMesh *mbt_sphere_mesh(float extent_x, float extent_y, float extent_z,
                         uint32_t segments_u, uint32_t segments_v,
                         bool inward_normals,
                         id<MDLMeshBufferAllocator> allocator) {
  return [[MDLMesh alloc]
      initSphereWithExtent:(vector_float3){extent_x, extent_y, extent_z}
                  segments:(vector_uint2){segments_u, segments_v}
             inwardNormals:inward_normals
              geometryType:MDLGeometryTypeTriangles
                 allocator:allocator];
}
