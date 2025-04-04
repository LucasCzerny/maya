package svk

import "core:log"

import vk "vendor:vulkan"

Descriptor_Group :: struct {
	sets:   []vk.DescriptorSet,
	layout: vk.DescriptorSetLayout,
}

create_descriptor_group :: proc(
	ctx: Context,
	bindings: []vk.DescriptorSetLayoutBinding,
	amount: u32,
	loc := #caller_location,
) -> (
	descriptor_group: Descriptor_Group,
) {
	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = cast(u32)len(bindings),
		pBindings    = raw_data(bindings),
	}

	result := vk.CreateDescriptorSetLayout(ctx.device, &layout_info, nil, &descriptor_group.layout)
	if result != .SUCCESS {
		log.panicf("Failed to create the descriptor set layout (result: %v)", result)
	}

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = ctx.descriptor_pool,
		descriptorSetCount = amount,
		pSetLayouts        = &descriptor_group.layout,
	}

	descriptor_group.sets = make([]vk.DescriptorSet, amount, loc = loc)
	result = vk.AllocateDescriptorSets(ctx.device, &alloc_info, raw_data(descriptor_group.sets))

	if result != .SUCCESS {
		log.panicf("Failed to allocate the descriptor set (result: %v)", result)
	}

	return
}

destroy_descriptor_group_layout :: proc(ctx: Context, descriptor_group: Descriptor_Group) {
	vk.DestroyDescriptorSetLayout(ctx.device, descriptor_group.layout, nil)
}

get_set :: proc(descriptor_group: Descriptor_Group, index: i32) -> Descriptor_Set {
	return Descriptor_Set{descriptor_group.sets[index], descriptor_group.layout}
}

