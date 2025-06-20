package main

import "shared:svk"

import vk "vendor:vulkan"

record_ray_tracing :: proc(
	ctx: svk.Context,
	pipeline: svk.Pipeline,
	command_buffer: vk.CommandBuffer,
	current_frame: u32,
) {
	data := cast(^Render_Data)context.user_ptr

	vk.CmdBindPipeline(command_buffer, .RAY_TRACING_KHR, pipeline.handle)

	width, height := ctx.window.width, ctx.window.height
	vk.CmdTraceRaysKHR(
		command_buffer,
		&data.shader_binding_table.ray_gen_region,
		&data.shader_binding_table.miss_region,
		&data.shader_binding_table.closest_hit_region,
		nil,
		width,
		height,
		1,
	)
}

