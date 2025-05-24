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

	svk.bind_uniform(
		ctx,
		data.camera_uniforms[current_frame],
		command_buffer,
		pipeline.layout,
		.COMPUTE,
		0,
	)
}

create_path_tracing_pipeline :: proc(ctx: svk.Context, data: Render_Data) -> svk.Pipeline {
	layout := data.camera_uniforms[0].descriptor.layout

	color_attachment := vk.AttachmentDescription {
		format         = ctx.swapchain.surface_format.format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	color_reference := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	depth_attachment := vk.AttachmentDescription {
		format         = ctx.swapchain.depth_format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .DONT_CARE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}

	depth_reference := vk.AttachmentReference {
		attachment = 1,
		layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription {
		pipelineBindPoint       = .GRAPHICS,
		colorAttachmentCount    = 1,
		pColorAttachments       = &color_reference,
		pDepthStencilAttachment = &depth_reference,
	}

	subpass_dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		srcAccessMask = {},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE},
	}

	attachments := [2]vk.AttachmentDescription{color_attachment, depth_attachment}

	render_pass_info := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = len(attachments),
		pAttachments    = raw_data(attachments[:]),
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &subpass_dependency,
	}

	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &layout,
	}

	config := svk.Graphics_Pipeline_Config {
		pipeline_layout_info   = pipeline_layout_info,
		render_pass_info       = render_pass_info,
		vertex_shader_source   = #load("../shaders/path_tracing.vert.spv", []u32),
		fragment_shader_source = #load("../shaders/path_tracing.frag.spv", []u32),
		binding_descriptions   = svk.binding_descriptions_from_attributes({.position}),
		attribute_descriptions = svk.attribute_descriptions_from_attributes({.position}),
		subpass                = 0,
		clear_color            = {0.2, 0.4, 0.85},
		record_fn              = record_path_tracing,
	}

	return svk.create_graphics_pipeline(ctx, config)
}

