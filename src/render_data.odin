package main

import "core:log"
import "core:math/linalg"

import "shared:svk"

import vk "vendor:vulkan"

Render_Data :: struct {
	models:                 []svk.Model,
	model_instances:        []Model_Instance,
	blas:                   []Acceleration_Structure,
	tlas:                   Acceleration_Structure,
	//
	ray_tracing_descriptor: svk.Descriptor_Set,
}

create_render_data :: proc(ctx: svk.Context) -> (data: Render_Data) {
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

	data.tlas = create_top_level_acceleration_structure(ctx, data.model_instances)

	data.ray_tracing_descriptor = create_ray_tracing_descriptor(ctx)

	return data
}

destroy_render_data :: proc(ctx: svk.Context, data: Render_Data) {
	// TODO: i kinda need that lmao
	for model in data.models {
		// svk.destroy_model(ctx, model)
	}

	for blas in data.blas {
		destroy_acceleration_structure(ctx, blas)
	}

	destroy_acceleration_structure(ctx, data.tlas)
}
