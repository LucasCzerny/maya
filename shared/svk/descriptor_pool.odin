package svk

import "core:log"

import vk "vendor:vulkan"

Descriptor_Config :: struct {
	max_sets:                  u32,
	nr_samplers:               u32,
	nr_combined_image_sampler: u32,
	nr_sampled_image:          u32,
	nr_storage_image:          u32,
	nr_uniform_texel_buffer:   u32,
	nr_storage_texel_buffer:   u32,
	nr_uniform_buffer:         u32,
	nr_storage_buffer:         u32,
	nr_uniform_buffer_dynamic: u32,
	nr_storage_buffer_dynamic: u32,
	nr_input_attachment:       u32,
}

@(private)
create_descriptor_pool :: proc(ctx: ^Context, config: Descriptor_Config) {
	all_pool_sizes := []vk.DescriptorPoolSize {
		{.SAMPLER, config.nr_samplers},
		{.COMBINED_IMAGE_SAMPLER, config.nr_combined_image_sampler},
		{.SAMPLED_IMAGE, config.nr_sampled_image},
		{.STORAGE_IMAGE, config.nr_storage_image},
		{.UNIFORM_TEXEL_BUFFER, config.nr_uniform_texel_buffer},
		{.STORAGE_TEXEL_BUFFER, config.nr_storage_texel_buffer},
		{.UNIFORM_BUFFER, config.nr_uniform_buffer},
		{.STORAGE_BUFFER, config.nr_storage_buffer},
		{.UNIFORM_BUFFER_DYNAMIC, config.nr_uniform_buffer_dynamic},
		{.STORAGE_BUFFER_DYNAMIC, config.nr_storage_buffer_dynamic},
		{.INPUT_ATTACHMENT, config.nr_input_attachment},
	}

	pool_sizes: [dynamic]vk.DescriptorPoolSize
	defer delete(pool_sizes)

	for pool_size in all_pool_sizes {
		if pool_size.descriptorCount != 0 {
			append(&pool_sizes, pool_size)
		}
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = config.max_sets,
		poolSizeCount = cast(u32)len(pool_sizes),
		pPoolSizes    = raw_data(pool_sizes),
	}

	result := vk.CreateDescriptorPool(ctx.device, &pool_info, nil, &ctx.descriptor_pool)
	if result != .SUCCESS {
		log.panicf("Failed to create the descriptor pool (result: %v)", result)
	}
}

