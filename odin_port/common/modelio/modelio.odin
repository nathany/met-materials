// Hand bindings for the sliver of Model I/O + MetalKit-mesh API the ports
// need. Odin's vendor libraries bind Metal and MTKView but not Model I/O or
// MTKMesh; these follow the same @(objc_class) / objc_send pattern as
// vendor:darwin/Metal.
//
// Requires Odin dev-2026-08 or later, which includes the `#simd` C-ABI fix
// (odin-lang/Odin#7010, fixed by PR #7015). Older compilers pass the
// vector arguments below in the wrong registers.
package modelio

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

@(require)
foreign import "system:ModelIO.framework"
@(require)
foreign import MetalKitFW "system:MetalKit.framework"

// Vector types as Apple's headers define them; vector_float3 is a
// 16-byte-aligned three-lane vector, i.e. four lanes with the last ignored.
vector_float3 :: #simd[4]f32
vector_uint2 :: #simd[2]u32

MDLGeometryType :: enum NS.Integer {
	Points         = 0,
	Lines          = 1,
	Triangles      = 2,
	TriangleStrips = 3,
	Quads          = 4,
}

// MDLMesh(sphereWithExtent:segments:inwardNormals:geometryType:allocator:)
// with geometryType fixed to .Triangles. Returns a +1 (owned) MDLMesh, per
// the Cocoa `new` naming convention; caller releases. Note: extent is the
// per-axis radius (semi-axis), not the diameter.
new_sphere :: proc "c" (
	extent: [3]f32,
	segments: [2]u32,
	inward_normals: bool,
	allocator: ^MTKMeshBufferAllocator,
) -> ^MDLMesh {
	return msgSend(
		^MDLMesh,
		MDLMesh.alloc(),
		"initSphereWithExtent:segments:inwardNormals:geometryType:allocator:",
		vector_float3{extent.x, extent.y, extent.z, 0},
		vector_uint2{segments.x, segments.y},
		inward_normals,
		MDLGeometryType.Triangles,
		allocator,
	)
}

// MDLMesh(coneWithExtent:segments:inwardNormals:cap:geometryType:allocator:)
// with geometryType fixed to .Triangles. Like new_sphere, this returns an
// owned object.
new_cone :: proc "c" (
	extent: [3]f32,
	segments: [2]u32,
	inward_normals: bool,
	cap: bool,
	allocator: ^MTKMeshBufferAllocator,
) -> ^MDLMesh {
	return msgSend(
		^MDLMesh,
		MDLMesh.alloc(),
		"initConeWithExtent:segments:inwardNormals:cap:geometryType:allocator:",
		vector_float3{extent.x, extent.y, extent.z, 0},
		vector_uint2{segments.x, segments.y},
		inward_normals,
		cap,
		MDLGeometryType.Triangles,
		allocator,
	)
}

foreign MetalKitFW {
	// MTKMetalVertexDescriptorFromModelIO (plain C function; autoreleased result).
	MTKMetalVertexDescriptorFromModelIO :: proc "c" (descriptor: ^MDLVertexDescriptor) -> ^MTL.VertexDescriptor ---
	// The inverse conversion, used to specify the layout while importing assets.
	MTKModelIOVertexDescriptorFromMetal :: proc "c" (descriptor: ^MTL.VertexDescriptor) -> ^MDLVertexDescriptor ---
}

@(private = "file")
msgSend :: intrinsics.objc_send

@(objc_class = "MDLVertexDescriptor")
MDLVertexDescriptor :: struct {
	using _: NS.Object,
}

@(objc_type = MDLVertexDescriptor, objc_name = "attributes")
MDLVertexDescriptor_attributes :: proc "c" (self: ^MDLVertexDescriptor) -> ^NS.MutableArray {
	return msgSend(^NS.MutableArray, self, "attributes")
}

@(objc_class = "MDLVertexAttribute")
MDLVertexAttribute :: struct {
	using _: NS.Object,
}

@(objc_type = MDLVertexAttribute, objc_name = "setName")
MDLVertexAttribute_setName :: proc "c" (self: ^MDLVertexAttribute, name: ^NS.String) {
	msgSend(nil, self, "setName:", name)
}

@(objc_class = "MDLAsset")
MDLAsset :: struct {
	using _: NS.Object,
}

@(objc_type = MDLAsset, objc_name = "alloc", objc_is_class_method = true)
MDLAsset_alloc :: proc "c" () -> ^MDLAsset {
	return msgSend(^MDLAsset, MDLAsset, "alloc")
}

@(objc_type = MDLAsset, objc_name = "init")
MDLAsset_init :: proc "c" (self: ^MDLAsset) -> ^MDLAsset {
	return msgSend(^MDLAsset, self, "init")
}

@(objc_type = MDLAsset, objc_name = "initWithURL")
MDLAsset_initWithURL :: proc "c" (
	self: ^MDLAsset,
	url: ^NS.URL,
	vertex_descriptor: ^MDLVertexDescriptor,
	buffer_allocator: ^MTKMeshBufferAllocator,
) -> ^MDLAsset {
	return msgSend(
		^MDLAsset,
		self,
		"initWithURL:vertexDescriptor:bufferAllocator:",
		url,
		vertex_descriptor,
		buffer_allocator,
	)
}

@(objc_type = MDLAsset, objc_name = "addObject")
MDLAsset_addObject :: proc "c" (self: ^MDLAsset, object: ^MDLMesh) {
	msgSend(nil, self, "addObject:", object)
}

@(objc_type = MDLAsset, objc_name = "canExportFileExtension", objc_is_class_method = true)
MDLAsset_canExportFileExtension :: proc "c" (extension: ^NS.String) -> bool {
	return msgSend(bool, MDLAsset, "canExportFileExtension:", extension)
}

@(objc_type = MDLAsset, objc_name = "exportAssetToURL")
MDLAsset_exportAssetToURL :: proc "contextless" (
	self: ^MDLAsset,
	url: ^NS.URL,
) -> (ok: bool, error: ^NS.Error) {
	ok = msgSend(bool, self, "exportAssetToURL:error:", url, &error)
	return
}

@(objc_type = MDLAsset, objc_name = "childObjectsOfClass")
MDLAsset_childObjectsOfClass :: proc "c" (self: ^MDLAsset, object_class: NS.Class) -> ^NS.Array {
	return msgSend(^NS.Array, self, "childObjectsOfClass:", object_class)
}

@(objc_class = "MDLMesh")
MDLMesh :: struct {
	using _: NS.Object,
}

@(objc_type = MDLMesh, objc_name = "alloc", objc_is_class_method = true)
MDLMesh_alloc :: proc "c" () -> ^MDLMesh {
	return msgSend(^MDLMesh, MDLMesh, "alloc")
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
