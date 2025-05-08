package svk

import "core:log"

import vk "vendor:vulkan"

@(private)
find_memory_type_index :: proc(
	ctx: Context,
	mem_requirements: vk.MemoryRequirements,
	properties: vk.MemoryPropertyFlags,
) -> u32 {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(ctx.physical_device, &mem_properties)

	for i in 0 ..< mem_properties.memoryTypeCount {
		if (mem_requirements.memoryTypeBits) & (1 << i) != 0 &&
		   (mem_properties.memoryTypes[i].propertyFlags & properties) == properties {
			return i
		}
	}

	log.panic("Failed to find a supported memory type")
}

