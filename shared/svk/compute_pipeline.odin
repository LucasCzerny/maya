package svk

import "core:log"

import vk "vendor:vulkan"

// odinfmt: disable
Compute_Pipeline_Config :: struct {
	pipeline_layout_info:  vk.PipelineLayoutCreateInfo,
	compute_shader_source: []u32,
	//
	record_fn:             proc(ctx: Context, pipeline: Pipeline, command_buffer: vk.CommandBuffer, current_frame: u32),
}
// odinfmt: enable

create_compute_pipeline :: proc(
	ctx: Context,
	config: Compute_Pipeline_Config,
) -> (
	pipeline: Pipeline,
) {
	pipeline_layout_info := config.pipeline_layout_info

	result := vk.CreatePipelineLayout(ctx.device, &pipeline_layout_info, nil, &pipeline.layout)
	if result != .SUCCESS {
		log.panicf("Failed to create the compute graphics pipeline layout (result: %v)", result)
	}

	log.ensure(
		len(config.compute_shader_source) != 0,
		"You need to set the compute shader source (use #load(\"path/to/shader\", []u32) f.e.)",
	)

	shader_module := create_shader_module(config.compute_shader_source, ctx.device)
	defer vk.DestroyShaderModule(ctx.device, shader_module, nil)

	pipeline_info := vk.ComputePipelineCreateInfo {
		sType = .COMPUTE_PIPELINE_CREATE_INFO,
		stage = {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.COMPUTE},
			module = shader_module,
			pName = "main",
		},
		layout = pipeline.layout,
	}

	result = vk.CreateComputePipelines(ctx.device, {}, 1, &pipeline_info, nil, &pipeline.handle)
	if result != .SUCCESS {
		log.panicf("Failed to create the compute pipeline (result: %v)", result)
	}

	pipeline.type = .compute
	pipeline.record_fn = config.record_fn

	return
}

destroy_compute_pipeline :: proc(ctx: Context, pipeline: Pipeline) {
	vk.DestroyPipeline(ctx.device, pipeline.handle, nil)
	vk.DestroyPipelineLayout(ctx.device, pipeline.layout, nil)
}

