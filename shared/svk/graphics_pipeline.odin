package svk

import "core:log"

import vk "vendor:vulkan"

// odinfmt: disable
Graphics_Pipeline_Config :: struct {
	pipeline_layout_info:                         vk.PipelineLayoutCreateInfo,
	render_pass_info:                             vk.RenderPassCreateInfo,
	vertex_shader_source, fragment_shader_source: []u32,
	binding_descriptions:                         []vk.VertexInputBindingDescription,
	attribute_descriptions:                       []vk.VertexInputAttributeDescription,
	subpass:                                      u32,
	//
	clear_color:                                  [3]f32,
	record_fn:                                    proc(ctx: Context, pipeline: Pipeline, command_buffer: vk.CommandBuffer, current_frame: u32),
	// all of these have a default value (see create_pipeline_handle)
	base_pipeline_index:                          Maybe(i32),
	base_pipeline_handle:                         Maybe(vk.Pipeline),
	viewport_info:                                Maybe(vk.PipelineViewportStateCreateInfo),
	input_assembly_info:                          Maybe(vk.PipelineInputAssemblyStateCreateInfo),
	rasterization_info:                           Maybe(vk.PipelineRasterizationStateCreateInfo),
	multisample_info:                             Maybe(vk.PipelineMultisampleStateCreateInfo),
	color_blend_attachment:                       Maybe(vk.PipelineColorBlendAttachmentState),
	color_blend_info:                             Maybe(vk.PipelineColorBlendStateCreateInfo),
	depth_stencil_info:                           Maybe(vk.PipelineDepthStencilStateCreateInfo),
	dynamic_state_enables:                        Maybe([]vk.DynamicState),
	dynamic_state_info:                           Maybe(vk.PipelineDynamicStateCreateInfo),
	tesselation_info:                             Maybe(vk.PipelineTessellationStateCreateInfo),
}
// odinfmt: enable

@(require_results)
create_graphics_pipeline :: proc(
	ctx: Context,
	config: Graphics_Pipeline_Config,
) -> (
	pipeline: Pipeline,
) {
	render_pass_info := config.render_pass_info
	result := vk.CreateRenderPass(ctx.device, &render_pass_info, nil, &pipeline.render_pass)
	if result != .SUCCESS {
		log.panicf("Failed to create the render pass (result: %v)", result)
	}

	pipeline_layout_info := config.pipeline_layout_info

	result = vk.CreatePipelineLayout(ctx.device, &pipeline_layout_info, nil, &pipeline.layout)
	if result != .SUCCESS {
		log.panicf("Failed to create the pipeline layout (result: %v)", result)
	}

	log.ensure(
		len(config.vertex_shader_source) != 0,
		"You need to set the vertex shader source (use #load(\"path/to/shader\", []u32) f.e.)",
	)
	log.ensure(
		len(config.fragment_shader_source) != 0,
		"You need to set the fragment shader source (use #load(\"path/to/shader\", []u32) f.e.)",
	)

	create_pipeline_handle(&pipeline, config, ctx.device)

	create_framebuffers(&pipeline, ctx.device, ctx.swapchain)

	pipeline.type = .graphics

	pipeline.clear_color = config.clear_color
	pipeline.record_fn = config.record_fn

	return
}

destroy_graphics_pipeline :: proc(ctx: Context, pipeline: Pipeline) {
	vk.DestroyPipeline(ctx.device, pipeline.handle, nil)
	vk.DestroyPipelineLayout(ctx.device, pipeline.layout, nil)
	vk.DestroyRenderPass(ctx.device, pipeline.render_pass, nil)

	for framebuffer in pipeline.framebuffers {
		vk.DestroyFramebuffer(ctx.device, framebuffer, nil)
	}

	delete(pipeline.framebuffers)
}

resize_pipeline :: proc(ctx: Context, pipeline: ^Pipeline) {
	create_framebuffers(pipeline, ctx.device, ctx.swapchain)
}

// chunky boi
@(private = "file")
create_pipeline_handle :: proc(
	pipeline: ^Pipeline,
	config: Graphics_Pipeline_Config,
	device: vk.Device,
) {
	vertex_module, fragment_module :=
		create_shader_module(config.vertex_shader_source, device),
		create_shader_module(config.fragment_shader_source, device)

	defer {
		vk.DestroyShaderModule(device, vertex_module, nil)
		vk.DestroyShaderModule(device, fragment_module, nil)
	}

	shader_stage_infos := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			stage = {.VERTEX},
			module = vertex_module,
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			stage = {.FRAGMENT},
			module = fragment_module,
		},
	}

	binding_descriptions := config.binding_descriptions
	attribute_descriptions := config.attribute_descriptions

	vertex_state_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = cast(u32)len(binding_descriptions),
		pVertexBindingDescriptions      = raw_data(binding_descriptions),
		vertexAttributeDescriptionCount = cast(u32)len(attribute_descriptions),
		pVertexAttributeDescriptions    = raw_data(attribute_descriptions),
	}

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType             = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount        = len(shader_stage_infos),
		pStages           = raw_data(shader_stage_infos[:]),
		pVertexInputState = &vertex_state_info,
		layout            = pipeline.layout,
		renderPass        = pipeline.render_pass,
		subpass           = config.subpass,
	}

	pipeline_info.basePipelineIndex = config.base_pipeline_index.? or_else -1
	pipeline_info.basePipelineHandle = config.base_pipeline_handle.? or_else {}

	viewport_info :=
		config.viewport_info.? or_else vk.PipelineViewportStateCreateInfo {
			sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			viewportCount = 1,
			pViewports = nil,
			scissorCount = 1,
			pScissors = nil,
		}
	pipeline_info.pViewportState = &viewport_info

	input_assembly_state :=
		config.input_assembly_info.? or_else vk.PipelineInputAssemblyStateCreateInfo {
			sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			topology = .TRIANGLE_LIST,
			primitiveRestartEnable = false,
		}
	pipeline_info.pInputAssemblyState = &input_assembly_state

	rasterization_info :=
		config.rasterization_info.? or_else vk.PipelineRasterizationStateCreateInfo {
			sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			depthClampEnable = false,
			rasterizerDiscardEnable = false,
			polygonMode = .FILL,
			lineWidth = 1,
			cullMode = {},
			frontFace = .COUNTER_CLOCKWISE,
			depthBiasEnable = false,
			depthBiasConstantFactor = 0,
			depthBiasClamp = 0,
			depthBiasSlopeFactor = 0,
		}
	pipeline_info.pRasterizationState = &rasterization_info

	multisample_info :=
		config.multisample_info.? or_else vk.PipelineMultisampleStateCreateInfo {
			sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
			sampleShadingEnable = false,
			rasterizationSamples = {._1},
			minSampleShading = 1,
			pSampleMask = nil,
			alphaToCoverageEnable = false,
			alphaToOneEnable = false,
		}
	pipeline_info.pMultisampleState = &multisample_info

	color_blend_attachment :=
		config.color_blend_attachment.? or_else vk.PipelineColorBlendAttachmentState {
			colorWriteMask = {.R, .G, .B, .A},
			blendEnable = false,
			srcColorBlendFactor = .ONE,
			dstColorBlendFactor = .ZERO,
			colorBlendOp = .ADD,
			srcAlphaBlendFactor = .ONE,
			dstAlphaBlendFactor = .ZERO,
			alphaBlendOp = .ADD,
		}

	color_blend_info :=
		config.color_blend_info.? or_else vk.PipelineColorBlendStateCreateInfo {
			sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			logicOpEnable = false,
			logicOp = .COPY,
			attachmentCount = 1,
			pAttachments = &color_blend_attachment,
			blendConstants = {0, 0, 0, 0},
		}
	pipeline_info.pColorBlendState = &color_blend_info

	depth_stencil_info :=
		config.depth_stencil_info.? or_else vk.PipelineDepthStencilStateCreateInfo {
			sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
			depthTestEnable = true,
			depthWriteEnable = true,
			depthCompareOp = .LESS,
			depthBoundsTestEnable = false,
			minDepthBounds = 0,
			maxDepthBounds = 1,
			stencilTestEnable = false,
			front = {},
			back = {},
		}
	pipeline_info.pDepthStencilState = &depth_stencil_info

	dynamic_state_enables :=
		config.dynamic_state_enables.? or_else []vk.DynamicState{.VIEWPORT, .SCISSOR}

	dynamic_state_info :=
		config.dynamic_state_info.? or_else vk.PipelineDynamicStateCreateInfo {
			sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			dynamicStateCount = cast(u32)len(dynamic_state_enables),
			pDynamicStates = raw_data(dynamic_state_enables[:]),
		}
	pipeline_info.pDynamicState = &dynamic_state_info

	tesselation_info :=
		config.tesselation_info.? or_else vk.PipelineTessellationStateCreateInfo {
			sType = .PIPELINE_TESSELLATION_STATE_CREATE_INFO,
			patchControlPoints = 0,
		}
	pipeline_info.pTessellationState = &tesselation_info

	result := vk.CreateGraphicsPipelines(
		device,
		vk.PipelineCache{},
		1,
		&pipeline_info,
		nil,
		&pipeline.handle,
	)
	if result != .SUCCESS {
		log.panicf("Failed to create the graphics pipline (result: %v)", result)
	}
}

@(private = "file")
create_framebuffers :: proc(pipeline: ^Pipeline, device: vk.Device, swapchain: Swapchain) {
	if len(pipeline.framebuffers) != 0 {
		destroy_framebuffers(pipeline, device)
		delete(pipeline.framebuffers)
	}

	pipeline.framebuffers = make([]vk.Framebuffer, swapchain.image_count)

	for i in 0 ..< swapchain.image_count {
		attachments := [2]vk.ImageView{swapchain.image_views[i], swapchain.depth_image_views[i]}

		framebuffer_info := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = pipeline.render_pass,
			attachmentCount = len(attachments),
			pAttachments    = raw_data(attachments[:]),
			width           = swapchain.extent.width,
			height          = swapchain.extent.height,
			layers          = 1,
		}

		result := vk.CreateFramebuffer(device, &framebuffer_info, nil, &pipeline.framebuffers[i])
		if result != .SUCCESS {
			log.panicf("Failed to create a graphics pipeline framebuffer (result: %v)", result)
		}
	}
}

@(private = "file")
destroy_framebuffers :: proc(pipeline: ^Pipeline, device: vk.Device) {
	for framebuffer in pipeline.framebuffers {
		vk.DestroyFramebuffer(device, framebuffer, nil)
	}
}

