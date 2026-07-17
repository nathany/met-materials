// Odin port of Metal by Tutorials, Chapter 1: Hello, Metal!
//
// The Swift originals are playgrounds that render a Model I/O sphere once
// into an MTKView live view. This port wraps the same code in a minimal
// AppKit application and redraws each frame via MTKView's delegate — the
// structure the book's own projects use from chapter 3 onward.
//
// Build & run from odin_port/:
//   ./run.sh 01-hello-metal                          # final: red sphere
//   ./run.sh 01-hello-metal -define:CHALLENGE=true   # challenge: green ellipse
package hello_metal

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import MTK "vendor:darwin/MetalKit"
import mdl "common:modelio"

CHALLENGE :: #config(CHALLENGE, false)

when CHALLENGE {
	TITLE :: "Chapter 1: Hello, Metal! (challenge)"
	SPHERE_EXTENT :: [3]f32{0.2, 0.75, 0.2}
	FRAGMENT_COLOR :: "float4(0, 0.4, 0.21, 1)"
} else {
	TITLE :: "Chapter 1: Hello, Metal!"
	SPHERE_EXTENT :: [3]f32{0.75, 0.75, 0.75}
	FRAGMENT_COLOR :: "float4(1, 0, 0, 1)"
}

// Same shader source as the playground, with the fragment color spliced in
// (the only line that differs between final and challenge).
SHADER_SOURCE :: `
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
  float4 position [[attribute(0)]];
};

vertex float4 vertex_main(const VertexIn vertex_in [[stage_in]]) {
  return vertex_in.position;
}

fragment float4 fragment_main() {
  return ` + FRAGMENT_COLOR + `;
}
`

// Everything the playground sets up before drawing. Lives for the whole run,
// so nothing here is released; the per-frame autorelease pool is in draw().
Renderer :: struct {
	command_queue:  ^MTL.CommandQueue,
	pipeline_state: ^MTL.RenderPipelineState,
	vertex_buffer:  ^MTL.Buffer,
	index_count:    NS.UInteger,
	index_type:     MTL.IndexType,
	index_buffer:   ^MTL.Buffer,
	index_offset:   NS.UInteger,
}

renderer: Renderer
view_delegate: MTK.ViewDelegate

renderer_init :: proc(device: ^MTL.Device, pixel_format: MTL.PixelFormat) {
	// Autoreleased setup temporaries (vertex descriptor, arrays) drain here;
	// everything Renderer keeps is either owned (+1) or retained by the mesh.
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->release()

	// let allocator = MTKMeshBufferAllocator(device: device)
	allocator := mdl.MTKMeshBufferAllocator.alloc()->initWithDevice(device)
	defer allocator->release()

	// let mdlMesh = MDLMesh(sphereWithExtent:segments:inwardNormals:geometryType:allocator:)
	mdl_mesh := mdl.new_sphere(SPHERE_EXTENT, {30, 30}, false, allocator)
	assert(mdl_mesh != nil, "failed to create MDLMesh sphere")
	defer mdl_mesh->release()

	// let mesh = try MTKMesh(mesh: mdlMesh, device: device)
	mesh, mesh_err := mdl.MTKMesh.alloc()->initWithMesh(mdl_mesh, device)
	fatal_on(mesh_err, "failed to convert MDLMesh to MTKMesh")
	// Kept alive forever (never released): it owns the GPU buffers below.

	renderer.command_queue = device->newCommandQueue()

	source := NS.String.alloc()->initWithOdinString(SHADER_SOURCE)
	defer source->release()
	library, lib_err := device->newLibraryWithSource(source, nil)
	fatal_on(lib_err, "failed to compile shaders")
	defer library->release()
	vertex_function := library->newFunctionWithName(NS.AT("vertex_main"))
	fragment_function := library->newFunctionWithName(NS.AT("fragment_main"))
	defer vertex_function->release()
	defer fragment_function->release()

	pipeline_descriptor := MTL.RenderPipelineDescriptor.alloc()->init()
	defer pipeline_descriptor->release()
	pipeline_descriptor->colorAttachments()->object(0)->setPixelFormat(pixel_format)
	pipeline_descriptor->setVertexFunction(vertex_function)
	pipeline_descriptor->setFragmentFunction(fragment_function)

	// pipelineDescriptor.vertexDescriptor = mdl.MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)
	pipeline_descriptor->setVertexDescriptor(
		mdl.MTKMetalVertexDescriptorFromModelIO(mesh->vertexDescriptor()),
	)

	pipeline_state, pso_err := device->newRenderPipelineState(pipeline_descriptor)
	fatal_on(pso_err, "failed to make a pipeline state")
	renderer.pipeline_state = pipeline_state

	// mesh.vertexBuffers[0].buffer / mesh.submeshes.first — the buffers are
	// retained by the (immortal) mesh.
	vertex_buffer := (^mdl.MTKMeshBuffer)(mesh->vertexBuffers()->object(0))
	renderer.vertex_buffer = vertex_buffer->buffer()

	submesh := (^mdl.MTKSubmesh)(mesh->submeshes()->object(0))
	index_buffer := submesh->indexBuffer()
	renderer.index_count = submesh->indexCount()
	renderer.index_type = submesh->indexType()
	renderer.index_buffer = index_buffer->buffer()
	renderer.index_offset = index_buffer->offset()
}

draw :: proc "c" (self: ^MTK.ViewDelegate, view: ^MTK.View) {
	// One pool per frame: drains the autoreleased drawable & command buffer.
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->release()

	descriptor := view->currentRenderPassDescriptor()
	drawable := view->currentDrawable()
	if descriptor == nil || drawable == nil {
		return
	}

	command_buffer := renderer.command_queue->commandBuffer()
	encoder := command_buffer->renderCommandEncoderWithDescriptor(descriptor)

	encoder->setRenderPipelineState(renderer.pipeline_state)
	encoder->setVertexBuffer(renderer.vertex_buffer, 0, 0)
	encoder->drawIndexedPrimitives(
		.Triangle,
		renderer.index_count,
		renderer.index_type,
		renderer.index_buffer,
		renderer.index_offset,
	)
	encoder->endEncoding()

	command_buffer->presentDrawable(drawable)
	command_buffer->commit()
}

drawable_size_will_change :: proc "c" (self: ^MTK.ViewDelegate, view: ^MTK.View, size: NS.Size) {
}

fatal_on :: proc(error: ^NS.Error, message: string) {
	if error != nil {
		fmt.eprintln(message, "-", error->localizedDescription()->odinString())
		runtime.trap()
	}
}

main :: proc() {
	// App setup happens before the run loop (which manages its own pools),
	// so it needs a pool of its own; drained just before run(). Everything
	// kept past the drain is owned (+1 from alloc-init), not autoreleased.
	setup_pool := NS.AutoreleasePool.alloc()->init()

	app := NS.Application.sharedApplication()
	app->setActivationPolicy(.Regular)

	app_delegate := NS.application_delegate_register_and_alloc(
		{applicationShouldTerminateAfterLastWindowClosed = proc(sender: ^NS.Application) -> NS.BOOL {
			return true
		}},
		"AppDelegate",
		context,
	)
	app->setDelegate(app_delegate)

	// guard let device = MTLCreateSystemDefaultDevice()
	device := MTL.CreateSystemDefaultDevice()
	assert(device != nil, "GPU is not supported")

	// let frame = CGRect(x: 0, y: 0, width: 500, height: 500)
	frame := NS.Rect{{0, 0}, {500, 500}}
	window := NS.Window.alloc()->initWithContentRect(
		frame,
		{.Titled, .Closable, .Miniaturizable},
		.Buffered,
		false,
	)

	// let view = MTKView(frame: frame, device: device)
	view := MTK.View.alloc()->initWithFrame(frame, device)
	view->setClearColor(MTL.ClearColor{1, 1, 0.8, 1})

	renderer_init(device, view->colorPixelFormat())

	view_delegate = MTK.ViewDelegate {
		drawInMTKView          = draw,
		drawableSizeWillChange = drawable_size_will_change,
	}
	view->setDelegate(&view_delegate)
	// MTKView holds its delegate *weakly*, and the vendor bridge wraps ours
	// in an autoreleased NSValue — without this retain, the setup pool would
	// deallocate the wrapper and drawing would silently stop.
	intrinsics.objc_send(^NS.Value, view, "delegate")->retain()

	window->setContentView(view)
	window->center()
	window->setTitle(NS.AT(TITLE))
	window->makeKeyAndOrderFront(nil)

	app->activate()
	setup_pool->release()
	app->run()
}
