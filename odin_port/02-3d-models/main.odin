// Odin port of Metal by Tutorials, Chapter 2: 3D Models.
//
// The chapter's two final playground pages and its challenge are selected at
// compile time:
//   just run 02-3d-models                            # import train.usdz
//   just run 02-3d-models -define:EXPORT_CONE=true   # render + export cone
//   just run 02-3d-models -define:CHALLENGE=true     # import mushroom.usdz
package three_d_models

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import MTK "vendor:darwin/MetalKit"
import mdl "common:modelio"

EXPORT_CONE :: #config(EXPORT_CONE, false)
CHALLENGE   :: #config(CHALLENGE, false)

#assert(!(EXPORT_CONE && CHALLENGE), "EXPORT_CONE and CHALLENGE are mutually exclusive")

when EXPORT_CONE {
	TITLE :: "Chapter 2: Render and Export a 3D Model"
} else when CHALLENGE {
	TITLE      :: "Chapter 2 Challenge: Import Mushroom"
	MODEL_PATH :: "../02-3d-models/projects/challenge/Chapter2.playground/Resources/mushroom.usdz"
} else {
	TITLE      :: "Chapter 2: Import Train"
	MODEL_PATH :: "../02-3d-models/projects/final/Chapter2.playground/Resources/train.usdz"
}

SHADER_HEADER :: `
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
  float4 position [[attribute(0)]];
};
`

when EXPORT_CONE {
	SHADER_SOURCE :: SHADER_HEADER + `
vertex float4 vertex_main(const VertexIn vertex_in [[stage_in]]) {
  return vertex_in.position;
}

fragment float4 fragment_main() {
  return float4(1, 0, 0, 1);
}
`
} else {
	SHADER_SOURCE :: SHADER_HEADER + `
vertex float4 vertex_main(const VertexIn vertex_in [[stage_in]]) {
  float4 position = vertex_in.position;
  position.y -= 1.0;
  return position;
}

fragment float4 fragment_main() {
  return float4(1, 0, 0, 1);
}
`
}

// The mesh owns the borrowed vertex buffer and the submeshes used by draw.
Renderer :: struct {
	mesh:           ^mdl.MTKMesh, // Owned; keeps borrowed GPU buffers alive.
	command_queue:  ^MTL.CommandQueue,
	pipeline_state: ^MTL.RenderPipelineState,
	vertex_buffer:  ^MTL.Buffer,
	vertex_offset:  NS.UInteger,
}

renderer: Renderer
view_delegate: MTK.ViewDelegate

// AppKit delegates are weak. Keep our owned references until app_shutdown.
Application_State :: struct {
	device:           ^MTL.Device,
	window:           ^NS.Window,
	view:             ^MTK.View,
	app_delegate:     ^NS.ApplicationDelegate,
	delegate_wrapper: ^NS.Value,
}

application: Application_State

renderer_init :: proc(device: ^MTL.Device, pixel_format: MTL.PixelFormat) {
	assert(renderer.mesh == nil, "destroy the renderer before initializing it again")
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->release()

	allocator := mdl.MTKMeshBufferAllocator.alloc()->initWithDevice(device)
	defer allocator->release()

	mdl_mesh: ^mdl.MDLMesh

	when EXPORT_CONE {
		// Page 1: generate a capped cone and export it as ASCII USD.
		mdl_mesh = mdl.new_cone({1, 1, 1}, {10, 10}, false, true, allocator)
		assert(mdl_mesh != nil, "failed to create MDLMesh cone")
		defer mdl_mesh->release()

		asset := mdl.MDLAsset.alloc()->init()
		defer asset->release()
		asset->addObject(mdl_mesh)

		extension := NS.AT("usda")
		assert(mdl.MDLAsset.canExportFileExtension(extension), "Model I/O cannot export .usda")

		export_path := absolute_path("generatedCone.usda")
		defer delete(export_path)
		export_url := file_url(export_path)
		defer export_url->release()

		ok, export_err := asset->exportAssetToURL(export_url)
		fatal_on(export_err, "failed to export generatedCone.usda")
		assert(ok, "failed to export generatedCone.usda")
		fmt.println("Exported", export_path)
	} else {
		// Page 2 / challenge: request position-only, tightly packed vertices.
		metal_descriptor := MTL.VertexDescriptor.alloc()->init()
		defer metal_descriptor->release()
		attribute := metal_descriptor->attributes()->object(0)
		attribute->setFormat(.Float3)
		attribute->setOffset(0)
		attribute->setBufferIndex(0)
		metal_descriptor->layouts()->object(0)->setStride(size_of([3]f32))

		mesh_descriptor := mdl.MTKModelIOVertexDescriptorFromMetal(metal_descriptor)
		position_attribute := (^mdl.MDLVertexAttribute)(mesh_descriptor->attributes()->object(0))
		position_attribute->setName(NS.AT("position"))

		model_path := absolute_path(MODEL_PATH)
		defer delete(model_path)
		assert(os.exists(model_path), fmt.tprintf("model not found at %s (use just run 02-3d-models)", model_path))

		model_url := file_url(model_path)
		defer model_url->release()
		asset := mdl.MDLAsset.alloc()->initWithURL(model_url, mesh_descriptor, allocator)
		assert(asset != nil, fmt.tprintf("failed to load %s", MODEL_PATH))
		defer asset->release()

		meshes := asset->childObjectsOfClass(NS.objc_lookUpClass("MDLMesh"))
		assert(meshes->count() > 0, fmt.tprintf("no MDLMesh found in %s", MODEL_PATH))
		mdl_mesh = (^mdl.MDLMesh)(meshes->object(0))
	}

	mesh, mesh_err := mdl.MTKMesh.alloc()->initWithMesh(mdl_mesh, device)
	fatal_on(mesh_err, "failed to convert MDLMesh to MTKMesh")
	assert(mesh != nil, "failed to create MTKMesh")
	renderer.mesh = mesh

	renderer.command_queue = device->newCommandQueue()
	assert(renderer.command_queue != nil, "failed to create Metal command queue")

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
	pipeline_descriptor->setVertexDescriptor(
		mdl.MTKMetalVertexDescriptorFromModelIO(mesh->vertexDescriptor()),
	)

	pipeline_state, pso_err := device->newRenderPipelineState(pipeline_descriptor)
	fatal_on(pso_err, "failed to make a pipeline state")
	renderer.pipeline_state = pipeline_state

	vertex_buffer := (^mdl.MTKMeshBuffer)(mesh->vertexBuffers()->object(0))
	renderer.vertex_buffer = vertex_buffer->buffer()
	// MTKMeshBuffers may share a Metal buffer; preserve this mesh's start.
	renderer.vertex_offset = vertex_buffer->offset()
}

absolute_path :: proc(relative_path: string) -> string {
	working_directory, err := os.get_working_directory(context.allocator)
	assert(err == nil, "failed to determine working directory")
	defer delete(working_directory)
	// This value outlives the current temporary-allocation scope and is deleted
	// by the caller, so it must use the persistent context allocator.
	return fmt.aprintf("%s/%s", working_directory, relative_path)
}

file_url :: proc(path: string) -> ^NS.URL {
	path_string := NS.String.alloc()->initWithOdinString(path)
	defer path_string->release()
	return NS.URL.alloc()->initFileURLWithPath(path_string)
}

// Call only while drawing is stopped. Default Metal command buffers retain
// their encoded resources until GPU work completes, including during shutdown.
renderer_destroy :: proc() {
	renderer.mesh->release()
	renderer.pipeline_state->release()
	renderer.command_queue->release()
	renderer = {}
}

draw :: proc "c" (self: ^MTK.ViewDelegate, view: ^MTK.View) {
	context = runtime.default_context()
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->release()

	descriptor := view->currentRenderPassDescriptor()
	drawable := view->currentDrawable()
	if descriptor == nil || drawable == nil {
		return
	}

	command_buffer := renderer.command_queue->commandBuffer()
	assert(command_buffer != nil, "failed to create Metal command buffer")
	encoder := command_buffer->renderCommandEncoderWithDescriptor(descriptor)
	assert(encoder != nil, "failed to create Metal render command encoder")
	encoder->setRenderPipelineState(renderer.pipeline_state)
	encoder->setVertexBuffer(renderer.vertex_buffer, renderer.vertex_offset, 0)
	encoder->setTriangleFillMode(.Lines)

	// The mesh owns its submeshes; iterate them directly, as in Swift.
	submeshes := renderer.mesh->submeshes()
	for index in 0 ..< submeshes->count() {
		submesh := (^mdl.MTKSubmesh)(submeshes->object(index))
		index_buffer := submesh->indexBuffer()
		encoder->drawIndexedPrimitives(
			.Triangle,
			submesh->indexCount(),
			submesh->indexType(),
			index_buffer->buffer(),
			index_buffer->offset(),
		)
	}
	encoder->endEncoding()

	command_buffer->presentDrawable(drawable)
	command_buffer->commit()
}

drawable_size_will_change :: proc "c" (self: ^MTK.ViewDelegate, view: ^MTK.View, size: NS.Size) {}

fatal_on :: proc(error: ^NS.Error, message: string) {
	if error != nil {
		fmt.eprintln(message, "-", error->localizedDescription()->odinString())
		runtime.trap()
	}
}

// applicationWillTerminate runs for both normal Quit and last-window close;
// AppKit may exit without returning from app->run(). Also safe to call twice.
app_shutdown :: proc() {
	if application.view == nil {
		return
	}
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->release()

	application.view->setPaused(true)
	// The vendor setDelegate(nil) would wrap a nil Odin pointer in NSValue.
	// Clear the Objective-C delegate itself before releasing its wrapper.
	intrinsics.objc_send(nil, application.view, "setDelegate:", rawptr(nil))
	renderer_destroy()
	application.delegate_wrapper->release()

	NS.Application.sharedApplication()->setDelegate(nil)
	application.window->setContentView(nil)
	application.view->release()
	application.window->release()
	application.device->release()
	application.app_delegate->release()
	application = {}
}

main :: proc() {
	setup_pool := NS.AutoreleasePool.alloc()->init()

	app := NS.Application.sharedApplication()
	app->setActivationPolicy(.Regular)
	app_delegate := NS.application_delegate_register_and_alloc(
		{
			applicationShouldTerminateAfterLastWindowClosed = proc(sender: ^NS.Application) -> NS.BOOL {
				return true
			},
			applicationWillTerminate = proc(notification: ^NS.Notification) {
				app_shutdown()
			},
		},
		"Chapter2AppDelegate",
		context,
	)
	app->setDelegate(app_delegate)

	device := MTL.CreateSystemDefaultDevice()
	assert(device != nil, "GPU is not supported")

	frame := NS.Rect{{0, 0}, {500, 500}}
	window := NS.Window.alloc()->initWithContentRect(
		frame,
		{.Titled, .Closable, .Miniaturizable},
		.Buffered,
		false,
	)
	// Keep ownership on close; app_shutdown balances our alloc/init.
	window->setReleasedWhenClosed(false)
	view := MTK.View.alloc()->initWithFrame(frame, device)
	view->setClearColor(MTL.ClearColor{1, 1, 0.8, 1})

	renderer_init(device, view->colorPixelFormat())

	view_delegate = MTK.ViewDelegate {
		drawInMTKView          = draw,
		drawableSizeWillChange = drawable_size_will_change,
	}
	view->setDelegate(&view_delegate)
	// MTKView's delegate is weak; retain MetalKit's autoreleased Odin bridge.
	delegate_wrapper := intrinsics.objc_send(^NS.Value, view, "delegate")
	delegate_wrapper->retain()
	application = {
		device           = device,
		window           = window,
		view             = view,
		app_delegate     = app_delegate,
		delegate_wrapper = delegate_wrapper,
	}

	window->setContentView(view)
	window->center()
	window->setTitle(NS.AT(TITLE))
	window->makeKeyAndOrderFront(nil)
	app->activate()

	setup_pool->release()
	app->run()
	app_shutdown() // Fallback if a caller stops the run loop instead of terminating.
}
