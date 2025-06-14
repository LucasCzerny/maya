package svk

import "core:log"

import vk "vendor:vulkan"

// odinfmt: disable
Ray_Tracing_Pipeline_Config :: struct {
	pipeline_layout_info:                         vk.PipelineLayoutCreateInfo,
	//
	ray_generation_shader_source: []u32,
	miss_shader_source:           []u32,
	closest_hit_shader_source:    []u32,
	any_hit_shader_source:        Maybe([]u32),
	intersection_shader_source:   Maybe([]u32),
	//
	max_ray_depth: u32,
	// 
	clear_color:                  [3]f32,
	record_fn:                    proc(ctx: Context, pipeline: Pipeline, command_buffer: vk.CommandBuffer, current_frame: u32),
}
// odinfmt: enable

create_ray_tracing_pipeline :: proc(
	ctx: Context,
	config: Ray_Tracing_Pipeline_Config,
) -> (
	pipeline: Pipeline,
) {
	log.ensure(
		len(config.ray_generation_shader_source) != 0,
		"You need to set the ray generation shader source (use #load(\"path/to/shader\", []u32) f.e.)",
	)

	log.ensure(
		len(config.miss_shader_source) != 0,
		"You need to set the miss shader source (use #load(\"path/to/shader\", []u32) f.e.)",
	)

	log.ensure(
		len(config.closest_hit_shader_source) != 0,
		"You need to set the closest hit shader source (use #load(\"path/to/shader\", []u32) f.e.)",
	)

	intersection_shader_source, intersection_present := config.intersection_shader_source.?
	any_hit_shader_source, any_hit_present := config.any_hit_shader_source.?

	nr_shaders := 3 + cast(int)intersection_present + cast(int)any_hit_present

	stages := make([]vk.PipelineShaderStageCreateInfo, nr_shaders)

	stages[0] = {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.RAYGEN_KHR},
		module = create_shader_module(config.ray_generation_shader_source, ctx.device),
		pName  = "main",
	}

	stages[1] = {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.MISS_KHR},
		module = create_shader_module(config.miss_shader_source, ctx.device),
		pName  = "main",
	}

	stages[2] = {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.CLOSEST_HIT_KHR},
		module = create_shader_module(config.closest_hit_shader_source, ctx.device),
		pName  = "main",
	}

	index := 3
	if any_hit_present {
		stages[index] = {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.ANY_HIT_KHR},
			module = create_shader_module(any_hit_shader_source, ctx.device),
			pName  = "main",
		}
	}

	if intersection_present {
		stages[index] = {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.INTERSECTION_KHR},
			module = create_shader_module(intersection_shader_source, ctx.device),
			pName  = "main",
		}

		index += 1
	}

	shader_groups := make([]vk.RayTracingShaderGroupCreateInfoKHR, nr_shaders)

	primitive_type: vk.RayTracingShaderGroupTypeKHR =
		intersection_present ? .TRIANGLES_HIT_GROUP : .PROCEDURAL_HIT_GROUP

	for stage, i in stages {
		stage_flags := stage.stage
		if .RAYGEN_KHR in stage_flags || .MISS_KHR in stage_flags {
			shader_groups[i] = {
				sType         = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
				type          = .GENERAL,
				generalShader = cast(u32)i,
			}
		} else if .CLOSEST_HIT_KHR in stage_flags {
			shader_groups[i] = {
				sType            = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
				type             = primitive_type,
				closestHitShader = cast(u32)i,
			}
		} else if .ANY_HIT_KHR in stage_flags {
			shader_groups[i] = {
				sType        = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
				type         = primitive_type,
				anyHitShader = cast(u32)i,
			}
		} else if .INTERSECTION_KHR in stage_flags {
			shader_groups[i] = {
				sType              = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
				type               = .TRIANGLES_HIT_GROUP,
				intersectionShader = cast(u32)i,
			}
		}
	}

	pipeline_layout_info := config.pipeline_layout_info

	result := vk.CreatePipelineLayout(ctx.device, &pipeline_layout_info, nil, &pipeline.layout)
	if result != .SUCCESS {
		log.panicf("Failed to create the pipeline layout (result: %v)", result)
	}

	pipeline_info := vk.RayTracingPipelineCreateInfoKHR {
		sType                        = .RAY_TRACING_PIPELINE_CREATE_INFO_KHR,
		stageCount                   = cast(u32)nr_shaders,
		pStages                      = raw_data(stages),
		groupCount                   = cast(u32)nr_shaders,
		pGroups                      = raw_data(shader_groups),
		maxPipelineRayRecursionDepth = config.max_ray_depth,
		layout                       = pipeline.layout,
		// basePipelineHandle           = pipeline.handle, // TODO: recreation mayhaps
		// basePipelineIndex            = i32,
	}

	result = vk.CreateRayTracingPipelinesKHR(
		ctx.device,
		nil,
		nil,
		1,
		&pipeline_info,
		nil,
		&pipeline.handle,
	)

	return {}
}

destroy_ray_tracing_pipeline :: proc(ctx: Context, pipeline: Pipeline) {
	vk.DestroyPipeline(ctx.device, pipeline.handle, nil)
	vk.DestroyPipelineLayout(ctx.device, pipeline.layout, nil)
}

