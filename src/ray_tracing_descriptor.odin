package main

import "shared:svk"

import vk "vendor:vulkan"

create_ray_tracing_descriptor :: proc(ctx: svk.Context) -> svk.Descriptor_Set {
	bindings: [2]vk.DescriptorSetLayoutBinding

	bindings[0] = {
		binding         = 1,
		descriptorType  = .ACCELERATION_STRUCTURE_KHR,
		descriptorCount = 1,
		stageFlags      = {.RAYGEN_KHR},
	}

	bindings[1] = {
		binding         = 0,
		descriptorType  = .STORAGE_IMAGE,
		descriptorCount = 1,
		stageFlags      = {.RAYGEN_KHR},
	}

	descriptor := svk.create_descriptor_set(ctx, bindings[:])
}
