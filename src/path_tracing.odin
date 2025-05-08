package main

import vk "vendor:vulkan"

import "shared:svk"

record_path_tracing :: proc(
	ctx: svk.Context,
	pipeline: svk.Pipeline,
	command_buffer: vk.CommandBuffer,
	current_frame: u32,
) {
	data := cast(^Render_Data)context.user_ptr

	svk.transition_image(
		ctx,
		data.storage_image,
		.UNDEFINED,
		.GENERAL,
		{.TOP_OF_PIPE},
		{.COMPUTE_SHADER},
		{},
		{.SHADER_READ},
		command_buffer,
	)

	svk.bind_descriptor_set(
		ctx,
		data.storage_image_descriptor,
		command_buffer,
		pipeline.layout,
		.COMPUTE,
		0,
	)

	svk.bind_descriptor_set(
		ctx,
		data.scene_descriptor,
		command_buffer,
		pipeline.layout,
		.COMPUTE,
		1,
	)

	svk.bind_uniform(
		ctx,
		data.camera_uniforms[current_frame],
		command_buffer,
		pipeline.layout,
		.COMPUTE,
		2,
	)

	screen_size := ctx.swapchain.extent
	vk.CmdDispatch(command_buffer, screen_size.width / 8, screen_size.height / 8, 1)

	svk.transition_image(
		ctx,
		data.storage_image,
		.GENERAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COMPUTE_SHADER},
		{.FRAGMENT_SHADER},
		{.SHADER_WRITE},
		{.SHADER_READ},
		command_buffer,
	)
}

create_path_tracing_pipeline :: proc(ctx: svk.Context, data: Render_Data) -> svk.Pipeline {
	layouts := [3]vk.DescriptorSetLayout {
		data.storage_image_descriptor.layout,
		data.scene_descriptor.layout,
		data.camera_uniforms[0].descriptor.layout,
	}

	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = len(layouts),
		pSetLayouts    = raw_data(layouts[:]),
	}

	pipeline_config := svk.Compute_Pipeline_Config {
		pipeline_layout_info  = pipeline_layout_info,
		compute_shader_source = #load("../shaders/path_tracing.comp.spv"),
		//
		record_fn             = record_path_tracing,
	}

	return svk.create_compute_pipeline(ctx, pipeline_config)
}

