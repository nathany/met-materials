//! Rust port of Metal by Tutorials, Chapter 1: Hello, Metal!
//!
//! The Swift originals are playgrounds that render a Model I/O sphere once
//! into an MTKView shown as the playground's live view. This port wraps the
//! same code in a minimal AppKit application (the playground page played
//! that role in Swift), and redraws each frame via `MTKViewDelegate` — the
//! structure every later chapter of the book uses.
//!
//! The `final` and `challenge` playgrounds differ only in sphere extent and
//! fragment color, so both binaries share this implementation.

#![deny(unsafe_op_in_unsafe_fn)]

mod simd;

use core::cell::OnceCell;

use objc2::rc::{Allocated, Retained};
use objc2::runtime::{Bool, ProtocolObject, Sel};
use objc2::{
    AnyThread, DefinedClass, MainThreadMarker, MainThreadOnly, define_class, msg_send, sel,
};
use objc2_app_kit::{
    NSApplication, NSApplicationActivationPolicy, NSApplicationDelegate, NSBackingStoreType,
    NSWindow, NSWindowStyleMask,
};
use objc2_foundation::{
    NSNotification, NSObject, NSObjectProtocol, NSPoint, NSRect, NSSize, NSString,
};
use objc2_metal::{
    MTLClearColor, MTLCommandBuffer, MTLCommandEncoder, MTLCommandQueue,
    MTLCreateSystemDefaultDevice, MTLDevice, MTLLibrary, MTLPixelFormat, MTLPrimitiveType,
    MTLRenderCommandEncoder, MTLRenderPipelineDescriptor, MTLRenderPipelineState,
};
use objc2_metal_kit::{
    MTKMesh, MTKMeshBufferAllocator, MTKMetalVertexDescriptorFromModelIO, MTKView, MTKViewDelegate,
};
use objc2_model_io::{MDLGeometryType, MDLMesh};

use crate::simd::{vector_float3, vector_uint2};

/// The two playgrounds in one: `final` vs `challenge` is just these values.
pub struct PlaygroundConfig {
    pub title: &'static str,
    pub sphere_extent: [f32; 3],
    pub fragment_color: [f32; 4],
}

// Same shader source as the playground, with the fragment color injected
// (the only line that differs between final and challenge).
fn shader_source(color: [f32; 4]) -> String {
    format!(
        r#"
#include <metal_stdlib>
using namespace metal;

struct VertexIn {{
  float4 position [[attribute(0)]];
}};

vertex float4 vertex_main(const VertexIn vertex_in [[stage_in]]) {{
  return vertex_in.position;
}}

fragment float4 fragment_main() {{
  return float4({:?}, {:?}, {:?}, {:?});
}}
"#,
        color[0], color[1], color[2], color[3]
    )
}

/// `MDLMesh(sphereWithExtent:segments:inwardNormals:geometryType:allocator:)`.
///
/// objc2 does not generate MDLMesh's procedural initializers because their
/// signatures contain simd vector types, and `msg_send!` can't express them
/// either (see `simd.rs`). Instead, call `objc_msgSend` through a function
/// pointer with the exact C signature — the same thing `msg_send!` compiles
/// down to, minus the debug-build encoding verification that simd arguments
/// currently fail.
fn sphere_mesh(
    extent: [f32; 3],
    segments: [u32; 2],
    allocator: &MTKMeshBufferAllocator,
) -> Retained<MDLMesh> {
    use core::arch::aarch64::{float32x4_t, uint32x2_t};

    // The lint is conservative about SIMD types in FFI; on aarch64 NEON is
    // always available and these types have the vector-register ABI we need.
    #[allow(improper_ctypes_definitions)]
    type InitSphereFn = unsafe extern "C-unwind" fn(
        *mut MDLMesh,              // self (from alloc, consumed by init)
        Sel,                       // _cmd
        float32x4_t,               // extent: vector_float3
        uint32x2_t,                // segments: vector_uint2
        Bool,                      // inwardNormals: BOOL
        MDLGeometryType,           // geometryType: NSInteger enum
        *const MTKMeshBufferAllocator, // allocator: id<MDLMeshBufferAllocator>
    ) -> *mut MDLMesh;

    // SAFETY: casting objc_msgSend to the target method's exact signature is
    // the documented way to call it; the signature above matches the
    // Objective-C declaration, with simd types as NEON register types.
    let init: InitSphereFn =
        unsafe { core::mem::transmute(objc2::ffi::objc_msgSend as *const core::ffi::c_void) };

    // alloc's +1 ownership transfers into init, which returns +1.
    let this = MDLMesh::alloc();
    let this_ptr = Allocated::as_ptr(&this).cast_mut();
    core::mem::forget(this);

    // SAFETY: see InitSphereFn; the receiver is a freshly allocated MDLMesh.
    let mesh = unsafe {
        init(
            this_ptr,
            sel!(initSphereWithExtent:segments:inwardNormals:geometryType:allocator:),
            vector_float3(extent),
            vector_uint2(segments),
            Bool::new(false),
            MDLGeometryType::Triangles,
            allocator,
        )
    };
    // SAFETY: init returns an owned (+1) object.
    unsafe { Retained::from_raw(mesh) }.expect("failed to create MDLMesh sphere")
}

/// Everything the playground sets up before drawing.
struct Renderer {
    command_queue: Retained<ProtocolObject<dyn MTLCommandQueue>>,
    pipeline_state: Retained<ProtocolObject<dyn MTLRenderPipelineState>>,
    mesh: Retained<MTKMesh>,
}

impl Renderer {
    fn new(
        device: &ProtocolObject<dyn MTLDevice>,
        pixel_format: MTLPixelFormat,
        config: &PlaygroundConfig,
    ) -> Self {
        let allocator =
            MTKMeshBufferAllocator::initWithDevice(MTKMeshBufferAllocator::alloc(), device);
        let mdl_mesh = sphere_mesh(config.sphere_extent, [30, 30], &allocator);
        let mesh = MTKMesh::initWithMesh_device_error(MTKMesh::alloc(), &mdl_mesh, device)
            .expect("failed to convert MDLMesh to MTKMesh");

        let command_queue = device.newCommandQueue().expect("failed to make a command queue");

        let source = NSString::from_str(&shader_source(config.fragment_color));
        let library = device
            .newLibraryWithSource_options_error(&source, None)
            .unwrap_or_else(|e| panic!("failed to compile shaders: {e}"));
        let vertex_function = library.newFunctionWithName(&NSString::from_str("vertex_main"));
        let fragment_function = library.newFunctionWithName(&NSString::from_str("fragment_main"));

        let pipeline_descriptor = MTLRenderPipelineDescriptor::new();
        // SAFETY: attachment 0 exists on every render pipeline descriptor.
        unsafe {
            pipeline_descriptor
                .colorAttachments()
                .objectAtIndexedSubscript(0)
                .setPixelFormat(pixel_format);
        }
        pipeline_descriptor.setVertexFunction(vertex_function.as_deref());
        pipeline_descriptor.setFragmentFunction(fragment_function.as_deref());

        let vertex_descriptor = MTKMetalVertexDescriptorFromModelIO(&mesh.vertexDescriptor());
        pipeline_descriptor.setVertexDescriptor(vertex_descriptor.as_deref());

        let pipeline_state = device
            .newRenderPipelineStateWithDescriptor_error(&pipeline_descriptor)
            .expect("failed to make a pipeline state");

        Self {
            command_queue,
            pipeline_state,
            mesh,
        }
    }

    fn draw(&self, view: &MTKView) {
        let Some(drawable) = view.currentDrawable() else {
            return;
        };
        let Some(render_pass_descriptor) = view.currentRenderPassDescriptor() else {
            return;
        };
        let command_buffer = self
            .command_queue
            .commandBuffer()
            .expect("failed to make a command buffer");
        let render_encoder = command_buffer
            .renderCommandEncoderWithDescriptor(&render_pass_descriptor)
            .expect("failed to make a render encoder");

        render_encoder.setRenderPipelineState(&self.pipeline_state);

        let vertex_buffer = self
            .mesh
            .vertexBuffers()
            .objectAtIndex(0)
            .buffer();
        // SAFETY: buffer index 0 matches `[[attribute(0)]]` via the vertex
        // descriptor's layout 0; offset 0 is within the buffer.
        unsafe {
            render_encoder.setVertexBuffer_offset_atIndex(Some(&vertex_buffer), 0, 0);
        }

        let submesh = self.mesh.submeshes().objectAtIndex(0);
        let index_buffer = submesh.indexBuffer();
        // SAFETY: index count/type/buffer/offset all come from the same
        // MTKSubmesh, so they describe valid index data.
        unsafe {
            render_encoder.drawIndexedPrimitives_indexCount_indexType_indexBuffer_indexBufferOffset(
                MTLPrimitiveType::Triangle,
                submesh.indexCount(),
                submesh.indexType(),
                &index_buffer.buffer(),
                index_buffer.offset(),
            );
        }

        render_encoder.endEncoding();
        command_buffer.presentDrawable(ProtocolObject::from_ref(&*drawable));
        command_buffer.commit();
    }
}

struct Ivars {
    config: PlaygroundConfig,
    renderer: OnceCell<Renderer>,
    window: OnceCell<Retained<NSWindow>>,
}

define_class!(
    // SAFETY:
    // - The superclass NSObject does not have any subclassing requirements.
    // - `MainThreadOnly` is correct, since this is an application delegate.
    // - `Delegate` does not implement `Drop`.
    #[unsafe(super(NSObject))]
    #[thread_kind = MainThreadOnly]
    #[ivars = Ivars]
    struct Delegate;

    unsafe impl NSObjectProtocol for Delegate {}

    unsafe impl NSApplicationDelegate for Delegate {
        #[unsafe(method(applicationDidFinishLaunching:))]
        fn application_did_finish_launching(&self, _notification: &NSNotification) {
            let mtm = self.mtm();
            let config = &self.ivars().config;

            // let frame = CGRect(x: 0, y: 0, width: 500, height: 500)
            let content_rect = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(500.0, 500.0));
            let style = NSWindowStyleMask::Titled
                | NSWindowStyleMask::Closable
                | NSWindowStyleMask::Miniaturizable;
            // SAFETY: standard window creation on the main thread.
            let window = unsafe {
                NSWindow::initWithContentRect_styleMask_backing_defer(
                    NSWindow::alloc(mtm),
                    content_rect,
                    style,
                    NSBackingStoreType::Buffered,
                    false,
                )
            };
            // We keep the window alive in an ivar; don't let AppKit release
            // it on close as well.
            unsafe { window.setReleasedWhenClosed(false) };

            let device = MTLCreateSystemDefaultDevice().expect("GPU is not supported");

            // let view = MTKView(frame: frame, device: device)
            let mtk_view =
                MTKView::initWithFrame_device(MTKView::alloc(mtm), content_rect, Some(&device));
            mtk_view.setClearColor(MTLClearColor {
                red: 1.0,
                green: 1.0,
                blue: 0.8,
                alpha: 1.0,
            });

            let renderer = Renderer::new(&device, mtk_view.colorPixelFormat(), config);
            self.ivars().renderer.set(renderer).ok().expect("renderer already set");

            let delegate = ProtocolObject::from_ref(self);
            mtk_view.setDelegate(Some(delegate));

            window.setContentView(Some(&mtk_view));
            window.center();
            window.setTitle(&NSString::from_str(config.title));
            window.makeKeyAndOrderFront(None);
            self.ivars().window.set(window).expect("window already set");

            NSApplication::sharedApplication(mtm).activate();
        }

        #[unsafe(method(applicationShouldTerminateAfterLastWindowClosed:))]
        fn should_terminate_after_last_window_closed(&self, _app: &NSApplication) -> bool {
            true
        }
    }

    unsafe impl MTKViewDelegate for Delegate {
        #[unsafe(method(drawInMTKView:))]
        fn draw_in_mtk_view(&self, view: &MTKView) {
            if let Some(renderer) = self.ivars().renderer.get() {
                renderer.draw(view);
            }
        }

        #[unsafe(method(mtkView:drawableSizeWillChange:))]
        fn mtk_view_drawable_size_will_change(&self, _view: &MTKView, _size: NSSize) {}
    }
);

impl Delegate {
    fn new(config: PlaygroundConfig, mtm: MainThreadMarker) -> Retained<Self> {
        let this = Self::alloc(mtm).set_ivars(Ivars {
            config,
            renderer: OnceCell::new(),
            window: OnceCell::new(),
        });
        // SAFETY: plain NSObject init.
        unsafe { msg_send![super(this), init] }
    }
}

/// The app shell: what `PlaygroundPage.current.liveView = view` did in Swift.
pub fn run(config: PlaygroundConfig) {
    let mtm = MainThreadMarker::new().expect("must run on the main thread");
    let app = NSApplication::sharedApplication(mtm);
    app.setActivationPolicy(NSApplicationActivationPolicy::Regular);

    let delegate = Delegate::new(config, mtm);
    app.setDelegate(Some(ProtocolObject::from_ref(&*delegate)));

    app.run();
}
