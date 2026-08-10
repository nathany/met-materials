// Odin port of Metal by Tutorials, Chapter 2: 3D Models.
//
// The chapter's two final playground pages and its challenge are selected at
// compile time:
//   ./run.sh 02-3d-models                            # import train.usdz
//   ./run.sh 02-3d-models -define:EXPORT_CONE=true   # render + export cone
//   ./run.sh 02-3d-models -define:CHALLENGE=true     # import mushroom.usdz
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

Submesh :: struct {
	index_count:  NS.UInteger,
	index_type:   MTL.IndexType,
	index_buffer: ^MTL.Buffer,
	index_offset: NS.UInteger,
}

Renderer :: struct {
	command_queue:  ^MTL.CommandQueue,
	pipeline_state: ^MTL.RenderPipelineState,
	vertex_buffer:  ^MTL.Buffer,
	submeshes:      [dynamic]Submesh,
}

renderer: Renderer
view_delegate: MTK.ViewDelegate

renderer_init :: proc(device: ^MTL.Device, pixel_format: MTL.PixelFormat) {
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
		assert(os.exists(model_path), fmt.tprintf("model not found at %s (run ./run.sh from odin_port/)", model_path))

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
	// Keep this owned MTKMesh alive: it owns the GPU buffers referenced below.

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
	pipeline_descriptor->setVertexDescriptor(
		mdl.MTKMetalVertexDescriptorFromModelIO(mesh->vertexDescriptor()),
	)

	pipeline_state, pso_err := device->newRenderPipelineState(pipeline_descriptor)
	fatal_on(pso_err, "failed to make a pipeline state")
	renderer.pipeline_state = pipeline_state

	vertex_buffer := (^mdl.MTKMeshBuffer)(mesh->vertexBuffers()->object(0))
	renderer.vertex_buffer = vertex_buffer->buffer()

	submeshes := mesh->submeshes()
	for index in 0 ..< submeshes->count() {
		submesh := (^mdl.MTKSubmesh)(submeshes->object(index))
		index_buffer := submesh->indexBuffer()
		append(&renderer.submeshes, Submesh {
			index_count  = submesh->indexCount(),
			index_type   = submesh->indexType(),
			index_buffer = index_buffer->buffer(),
			index_offset = index_buffer->offset(),
		})
	}
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

draw :: proc "c" (self: ^MTK.ViewDelegate, view: ^MTK.View) {
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
	encoder->setTriangleFillMode(.Lines)

	for submesh in renderer.submeshes {
		encoder->drawIndexedPrimitives(
			.Triangle,
			submesh.index_count,
			submesh.index_type,
			submesh.index_buffer,
			submesh.index_offset,
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

main :: proc() {
	setup_pool := NS.AutoreleasePool.alloc()->init()

	app := NS.Application.sharedApplication()
	app->setActivationPolicy(.Regular)
	app_delegate := NS.application_delegate_register_and_alloc(
		{applicationShouldTerminateAfterLastWindowClosed = proc(sender: ^NS.Application) -> NS.BOOL {
			return true
		}},
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
	view := MTK.View.alloc()->initWithFrame(frame, device)
	view->setClearColor(MTL.ClearColor{1, 1, 0.8, 1})

	renderer_init(device, view->colorPixelFormat())

	view_delegate = MTK.ViewDelegate {
		drawInMTKView          = draw,
		drawableSizeWillChange = drawable_size_will_change,
	}
	view->setDelegate(&view_delegate)
	// MTKView's delegate is weak; retain MetalKit's autoreleased Odin bridge.
	intrinsics.objc_send(^NS.Value, view, "delegate")->retain()

	window->setContentView(view)
	window->center()
	window->setTitle(NS.AT(TITLE))
	window->makeKeyAndOrderFront(nil)
	app->activate()

	setup_pool->release()
	app->run()
}
