package svk

import "core:log"

import "vendor:glfw"
import vk "vendor:vulkan"

Window_Config :: struct {
	window_title:   cstring,
	initial_width:  i32,
	initial_height: i32,
	resizable:      bool,
	fullscreen:     bool,
}

Window :: struct {
	handle:  glfw.WindowHandle,
	surface: vk.SurfaceKHR,
	width:   u32,
	height:  u32,
}

create_window :: proc(window: ^Window, config: Window_Config, instance: vk.Instance) {
	assert(!config.fullscreen, "Fullscreen is not implemented yet")

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, cast(b32)config.resizable)

	window.handle = glfw.CreateWindow(
		config.initial_width,
		config.initial_height,
		config.window_title,
		nil,
		nil,
	)

	window.width = cast(u32)config.initial_width
	window.height = cast(u32)config.initial_height

	result := glfw.CreateWindowSurface(instance, window.handle, nil, &window.surface)
	if result != .SUCCESS {
		log.panic("Failed to create the window surface")
	}

	glfw.SetFramebufferSizeCallback(window.handle, cast(glfw.FramebufferSizeProc)set_window_size)
}

destroy_window :: proc(ctx: Context, window: Window) {
	vk.DestroySurfaceKHR(ctx.instance, window.surface, nil)
}

@(private = "file")
set_window_size :: proc "c" (handle: glfw.WindowHandle, width: i32, height: i32) {
	window := cast(^Window)glfw.GetWindowUserPointer(handle)

	window.width = cast(u32)width
	window.height = cast(u32)height
}

