package main

import "core:log"
import "core:math/linalg"

import "shared:svk"

import vk "vendor:vulkan"

Render_Data :: struct {
	properties:             vk.PhysicalDeviceProperties2,
	pipeline_properties:    vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
	//
	models:                 []svk.Model,
	model_instances:        []Model_Instance,
	blas:                   []Acceleration_Structure,
	tlas:                   Acceleration_Structure,
	//
	storage_image:          svk.Image,
	sampler:                vk.Sampler,
	camera:                 Camera,
	camera_buffer:          svk.Buffer,
	ray_tracing_descriptor: svk.Descriptor_Set,
	//
	ray_tracing_pipeline:   svk.Pipeline,
	shader_binding_table:   Shader_Binding_Table,
}

create_render_data :: proc(ctx: svk.Context) -> (data: Render_Data) {
	// TODO: ctx.physical_device or all of it
	data.properties, data.pipeline_properties = query_physical_device_properties(
		ctx.physical_device,
	)

	boom_box, err := svk.load_model(
		ctx,
		"models/boom_box.glb",
		{.position, .normal},
		{.base_color},
		{.VERTEX_BUFFER, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
		{.INDEX_BUFFER, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
	)
	if err != nil {
		log.panicf("Failed to load the boom box model (err: %v)", err)
	}

	data.models = make([]svk.Model, 1)
	data.models[0] = boom_box

	data.blas = create_bottom_level_acceleration_structures(ctx, data.models)

	data.model_instances = make([]Model_Instance, 1)
	data.model_instances[0] = {
		model     = &data.models[0], // TODO: does boom_box work?
		blas      = &data.blas[0],
		transform = linalg.matrix4_scale([3]f32{10, 10, 10}),
	}

	data.storage_image = svk.create_image(
		ctx,
		ctx.window.width,
		ctx.window.height,
		1,
		3,
		false,
		layout = .GENERAL,
	)
	data.tlas = create_top_level_acceleration_structure(ctx, data.model_instances)

	data.sampler = create_sampler(ctx)

	data.camera = create_camera(ctx, ctx.window.width, ctx.window.height)

	data.camera_buffer = svk.create_buffer(
		ctx,
		size_of(Camera),
		1,
		{.UNIFORM_BUFFER},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)

	svk.copy_to_buffer(ctx, &data.camera_buffer, &data.camera)

	data.ray_tracing_descriptor = create_ray_tracing_descriptor(
		ctx,
		data.tlas,
		data.storage_image,
		data.sampler,
		data.models[0].meshes[0].primitives[0].vertex_buffers[.position],
	)

	layout_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &data.ray_tracing_descriptor.layout,
	}

	pipeline_config := svk.Ray_Tracing_Pipeline_Config {
		pipeline_layout_info         = layout_info,
		ray_generation_shader_source = #load("../shaders/basic.rgen.spv", []u32),
		miss_shader_source           = #load("../shaders/basic.miss.spv", []u32),
		closest_hit_shader_source    = #load("../shaders/basic.rchit.spv", []u32),
		max_ray_depth                = 1,
		clear_color                  = {0.1, 0.1, 0.4},
		record_fn                    = nil,
	}

	data.ray_tracing_pipeline = svk.create_ray_tracing_pipeline(ctx, pipeline_config)

	data.shader_binding_table = create_shader_binding_table(
		ctx,
		data.ray_tracing_pipeline,
		data.pipeline_properties,
	)

	return data
}

destroy_render_data :: proc(ctx: svk.Context, data: Render_Data) {
	// TODO: i kinda need that lmao
	// for model in data.models {
	// svk.destroy_model(ctx, model)
	// }

	for blas in data.blas {
		destroy_acceleration_structure(ctx, blas)
	}

	destroy_acceleration_structure(ctx, data.tlas)
}

@(private = "file")
query_physical_device_properties :: proc(
	physical_device: vk.PhysicalDevice,
) -> (
	vk.PhysicalDeviceProperties2,
	vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
) {
	ray_tracing_pipeline_properties := vk.PhysicalDeviceRayTracingPipelinePropertiesKHR {
		sType = .PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_PROPERTIES_KHR,
	}

	properties := vk.PhysicalDeviceProperties2 {
		sType = .PHYSICAL_DEVICE_PROPERTIES_2,
		pNext = &ray_tracing_pipeline_properties,
	}

	vk.GetPhysicalDeviceProperties2(physical_device, &properties)

	return properties, ray_tracing_pipeline_properties
}

@(private = "file")
create_sampler :: proc(ctx: svk.Context) -> (sampler: vk.Sampler) {
	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(ctx.physical_device, &properties)

	create_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		mipmapMode              = .LINEAR,
		addressModeU            = .CLAMP_TO_EDGE,
		addressModeV            = .CLAMP_TO_EDGE,
		addressModeW            = .CLAMP_TO_EDGE,
		mipLodBias              = 0,
		anisotropyEnable        = true,
		maxAnisotropy           = properties.limits.maxSamplerAnisotropy,
		compareEnable           = false,
		compareOp               = .NEVER,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
	}

	result := vk.CreateSampler(ctx.device, &create_info, nil, &sampler)
	if result != .SUCCESS {
		log.panicf("Failed to create the storage image sampler (result: %v)", result)
	}

	return sampler
}

@(private = "file")
create_ray_tracing_descriptor :: proc(
	ctx: svk.Context,
	tlas: Acceleration_Structure,
	storage_image: svk.Image,
	sampler: vk.Sampler,
	camera_buffer: svk.Buffer,
	vertex_buffer: svk.Buffer,
) -> svk.Descriptor_Set {
	tlas := tlas

	bindings: [4]vk.DescriptorSetLayoutBinding

	bindings[0] = {
		binding         = 0,
		descriptorType  = .ACCELERATION_STRUCTURE_KHR,
		descriptorCount = 1,
		stageFlags      = {.RAYGEN_KHR},
	}

	bindings[1] = {
		binding         = 1,
		descriptorType  = .STORAGE_IMAGE,
		descriptorCount = 1,
		stageFlags      = {.RAYGEN_KHR},
	}

	bindings[2] = {
		binding         = 2,
		descriptorType  = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags      = {.RAYGEN_KHR},
	}

	bindings[3] = {
		binding         = 3,
		descriptorType  = .STORAGE_BUFFER,
		descriptorCount = 1,
		stageFlags      = {.CLOSEST_HIT_KHR},
	}

	descriptor := svk.create_descriptor_set(ctx, bindings[:])

	tlas_buffer_info := vk.DescriptorBufferInfo {
		buffer = tlas.buffer.handle,
		range  = tlas.buffer.size,
	}

	tlas_write_info := vk.WriteDescriptorSetAccelerationStructureKHR {
		sType                      = .WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
		accelerationStructureCount = 1,
		pAccelerationStructures    = &tlas.handle,
	}

	svk.update_descriptor_set(ctx, descriptor, tlas_buffer_info, 0, p_next = &tlas_write_info)

	storage_image_info := vk.DescriptorImageInfo {
		sampler     = sampler,
		imageView   = storage_image.view,
		imageLayout = storage_image.layout,
	}

	svk.update_descriptor_set_image(ctx, descriptor, storage_image_info, 1)

	camera_buffer_info := vk.DescriptorBufferInfo {
		buffer = camera_buffer.handle,
		range  = camera_buffer.size,
	}

	svk.update_descriptor_set_buffer(ctx, descriptor, camera_buffer_info, 3, .STORAGE_BUFFER)

	vertex_buffer_info := vk.DescriptorBufferInfo {
		buffer = vertex_buffer.handle,
		range  = vertex_buffer.size,
	}

	svk.update_descriptor_set_buffer(ctx, descriptor, vertex_buffer_info, 3, .STORAGE_BUFFER)

	return descriptor
}

