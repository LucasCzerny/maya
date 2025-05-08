package main

import "core:log"
// import "core:math/linalg"

import vk "vendor:vulkan"

import "shared:svk"

Render_Data :: struct {
	storage_image:            svk.Image,
	storage_image_descriptor: svk.Descriptor_Set,
	frame_descriptor:         svk.Descriptor_Set,
	compute_shader_sampler:   vk.Sampler,
	//
	scene_descriptor:         svk.Descriptor_Set,
	models:                   []svk.Model,
	primitive_list:           Primitive_List,
	//
	quad_vertex_buffer:       svk.Buffer,
	quad_index_buffer:        svk.Buffer,
	//
	camera:                   Camera,
	camera_uniforms:          [MAX_FRAMES_IN_FLIGHT]svk.Uniform,
}

create_render_data :: proc(ctx: svk.Context) -> Render_Data {
	width := ctx.window.width
	height := ctx.window.height

	storage_image_binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = .STORAGE_IMAGE,
		descriptorCount = 1,
		stageFlags      = {.COMPUTE},
	}

	frame_binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = 1,
		stageFlags      = {.FRAGMENT},
	}

	data := Render_Data {
		storage_image            = svk.create_image(
			ctx,
			width,
			height,
			8,
			4,
			false, // storage iamge no likey srgb
			layout = .GENERAL,
			usage = {.SAMPLED, .STORAGE, .TRANSFER_DST},
		),
		storage_image_descriptor = svk.create_descriptor_set(ctx, {storage_image_binding}),
		frame_descriptor         = svk.create_descriptor_set(ctx, {frame_binding}),
		compute_shader_sampler   = create_sampler(ctx),
		//
		scene_descriptor         = create_scene_descriptor(ctx),
		models                   = make([]svk.Model, 1),
		//
		quad_vertex_buffer       = svk.create_buffer(
			ctx,
			size_of(f32),
			4 * (2 + 2),
			{.VERTEX_BUFFER},
			{.HOST_COHERENT, .DEVICE_LOCAL},
		),
		quad_index_buffer        = svk.create_buffer(
			ctx,
			size_of(u32),
			6,
			{.INDEX_BUFFER},
			{.HOST_COHERENT, .DEVICE_LOCAL},
		),
	}

	image_info := vk.DescriptorImageInfo {
		sampler     = data.compute_shader_sampler,
		imageView   = data.storage_image.view,
		imageLayout = .GENERAL,
	}
	svk.update_descriptor_set_image(
		ctx,
		data.storage_image_descriptor,
		image_info,
		0,
		descriptor_type = .STORAGE_IMAGE,
	)

	image_info.imageLayout = .SHADER_READ_ONLY_OPTIMAL
	svk.update_descriptor_set(ctx, data.frame_descriptor, image_info, 0)

	// boom_box, err := svk.load_model(ctx, "models/BoomBox.glb", attributes, texture_types)
	// if err != nil {
	// 	log.panicf("failed to load the boom box (err: %v)", err)
	// }

	// data.models[0] = boom_box

	attributes :: bit_set[svk.Model_Attribute]{.position, .normal, .tangent, .tex_coord}
	texture_types :: bit_set[svk.Model_Texture_Type]{.base_color}

	cube, err := svk.load_model(
		ctx,
		"models/BoxTextured.glb",
		attributes,
		texture_types,
		force_u32_indices = true,
	)
	if err != nil {
		log.panicf("Failed to load the cube (err: %v)", err)
	}

	data.models[0] = cube
	data.primitive_list = create_primitive_list(ctx, data.models)

	update_scene_descriptor(ctx, data.scene_descriptor, data.primitive_list)
	
	// odinfmt: disable
	vertices := [4 * (2 + 2)]f32{
		-1.0, -1.0, /**/ 0.0, 0.0,
		 1.0, -1.0, /**/ 1.0, 0.0,
		 1.0,  1.0, /**/ 1.0, 1.0,
		-1.0,  1.0, /**/ 0.0, 1.0,
	}
	// odinfmt: enable

	indices := [6]u32{0, 1, 2, 2, 3, 0}

	svk.copy_to_buffer(ctx, &data.quad_vertex_buffer, raw_data(vertices[:]))
	svk.copy_to_buffer(ctx, &data.quad_index_buffer, raw_data(indices[:]))

	data.camera = create_camera(ctx)

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		data.camera_uniforms[i] = svk.create_uniform(ctx, size_of(Camera), 1, {.COMPUTE})
	}

	return data
}

update_render_data :: proc(
	ctx: svk.Context,
	data: ^Render_Data,
	current_frame: u32,
	delta_time: f64,
) {
	@(static) first_frame := true

	changed := update_camera(ctx, &data.camera, delta_time)
	if !changed && !first_frame && false {
		return
	}

	first_frame = false

	svk.update_uniform(ctx, &data.camera_uniforms[current_frame], &data.camera)
}

destroy_render_data :: proc(ctx: svk.Context, data: Render_Data) {
	// svk.destroy_model(ctx, data.model)
	// view_projection_matrix := calculate_view_projection_matrix(ctx, data.camera)
}

@(private = "file")
create_sampler :: proc(ctx: svk.Context) -> (sampler: vk.Sampler) {
	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(ctx.physical_device, &properties)

	sampler_info := vk.SamplerCreateInfo {
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
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
	}

	result := vk.CreateSampler(ctx.device, &sampler_info, nil, &sampler)
	if result != .SUCCESS {
		log.panicf("Failed to create the compute shader sampler (result: %v)", result)
	}

	return
}

