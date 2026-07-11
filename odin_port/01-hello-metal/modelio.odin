// Hand bindings for the sliver of Model I/O + MetalKit-mesh API chapter 1
// needs. Odin's vendor libraries bind Metal and MTKView but not Model I/O or
// MTKMesh; these follow the same @(objc_class) / objc_send pattern as
// vendor:darwin/Metal.
//
// Every method here has a simd-free signature, which is what makes direct
// binding possible — the one simd-typed call (the sphere initializer) lives
// in shim/sphere_shim.m instead. See Metal-odin-port-plan.md §3.10.
package hello_metal

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

@(require)
foreign import "system:ModelIO.framework"
@(require)
foreign import MetalKitFW "system:MetalKit.framework"

foreign import sphere_shim "shim/sphere_shim.o"

foreign sphere_shim {
	// Returns a +1 (owned) MDLMesh; caller releases.
	mbt_sphere_mesh :: proc "c" (
		extent_x, extent_y, extent_z: f32,
		segments_u, segments_v: u32,
		inward_normals: bool,
		allocator: ^MTKMeshBufferAllocator,
	) -> ^MDLMesh ---
}

foreign MetalKitFW {
	// MTKMetalVertexDescriptorFromModelIO (plain C function; autoreleased result).
	MTKMetalVertexDescriptorFromModelIO :: proc "c" (descriptor: ^MDLVertexDescriptor) -> ^MTL.VertexDescriptor ---
}

@(private = "file")
msgSend :: intrinsics.objc_send

@(objc_class = "MDLVertexDescriptor")
MDLVertexDescriptor :: struct {
	using _: NS.Object,
}

@(objc_class = "MDLMesh")
MDLMesh :: struct {
	using _: NS.Object,
}

@(objc_class = "MTKMeshBufferAllocator")
MTKMeshBufferAllocator :: struct {
	using _: NS.Object,
}

@(objc_type = MTKMeshBufferAllocator, objc_name = "alloc", objc_is_class_method = true)
MTKMeshBufferAllocator_alloc :: proc "c" () -> ^MTKMeshBufferAllocator {
	return msgSend(^MTKMeshBufferAllocator, MTKMeshBufferAllocator, "alloc")
}

@(objc_type = MTKMeshBufferAllocator, objc_name = "initWithDevice")
MTKMeshBufferAllocator_initWithDevice :: proc "c" (
	self: ^MTKMeshBufferAllocator,
	device: ^MTL.Device,
) -> ^MTKMeshBufferAllocator {
	return msgSend(^MTKMeshBufferAllocator, self, "initWithDevice:", device)
}

@(objc_class = "MTKMesh")
MTKMesh :: struct {
	using _: NS.Object,
}

@(objc_type = MTKMesh, objc_name = "alloc", objc_is_class_method = true)
MTKMesh_alloc :: proc "c" () -> ^MTKMesh {
	return msgSend(^MTKMesh, MTKMesh, "alloc")
}

@(objc_type = MTKMesh, objc_name = "initWithMesh")
MTKMesh_initWithMesh :: proc "contextless" (
	self: ^MTKMesh,
	mesh: ^MDLMesh,
	device: ^MTL.Device,
) -> (
	mtk_mesh: ^MTKMesh,
	error: ^NS.Error,
) {
	mtk_mesh = msgSend(^MTKMesh, self, "initWithMesh:device:error:", mesh, device, &error)
	return
}

@(objc_type = MTKMesh, objc_name = "vertexDescriptor")
MTKMesh_vertexDescriptor :: proc "c" (self: ^MTKMesh) -> ^MDLVertexDescriptor {
	return msgSend(^MDLVertexDescriptor, self, "vertexDescriptor")
}

@(objc_type = MTKMesh, objc_name = "vertexBuffers")
MTKMesh_vertexBuffers :: proc "c" (self: ^MTKMesh) -> ^NS.Array {
	return msgSend(^NS.Array, self, "vertexBuffers")
}

@(objc_type = MTKMesh, objc_name = "submeshes")
MTKMesh_submeshes :: proc "c" (self: ^MTKMesh) -> ^NS.Array {
	return msgSend(^NS.Array, self, "submeshes")
}

@(objc_class = "MTKMeshBuffer")
MTKMeshBuffer :: struct {
	using _: NS.Object,
}

@(objc_type = MTKMeshBuffer, objc_name = "buffer")
MTKMeshBuffer_buffer :: proc "c" (self: ^MTKMeshBuffer) -> ^MTL.Buffer {
	return msgSend(^MTL.Buffer, self, "buffer")
}

@(objc_type = MTKMeshBuffer, objc_name = "offset")
MTKMeshBuffer_offset :: proc "c" (self: ^MTKMeshBuffer) -> NS.UInteger {
	return msgSend(NS.UInteger, self, "offset")
}

@(objc_class = "MTKSubmesh")
MTKSubmesh :: struct {
	using _: NS.Object,
}

@(objc_type = MTKSubmesh, objc_name = "primitiveType")
MTKSubmesh_primitiveType :: proc "c" (self: ^MTKSubmesh) -> MTL.PrimitiveType {
	return msgSend(MTL.PrimitiveType, self, "primitiveType")
}

@(objc_type = MTKSubmesh, objc_name = "indexCount")
MTKSubmesh_indexCount :: proc "c" (self: ^MTKSubmesh) -> NS.UInteger {
	return msgSend(NS.UInteger, self, "indexCount")
}

@(objc_type = MTKSubmesh, objc_name = "indexType")
MTKSubmesh_indexType :: proc "c" (self: ^MTKSubmesh) -> MTL.IndexType {
	return msgSend(MTL.IndexType, self, "indexType")
}

@(objc_type = MTKSubmesh, objc_name = "indexBuffer")
MTKSubmesh_indexBuffer :: proc "c" (self: ^MTKSubmesh) -> ^MTKMeshBuffer {
	return msgSend(^MTKMeshBuffer, self, "indexBuffer")
}
