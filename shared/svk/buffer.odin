package svk

import "core:log"
import "core:math"
import "core:mem"

import vk "vendor:vulkan"

Buffer :: struct {
	handle:        vk.Buffer,
	memory:        vk.DeviceMemory,
	count:         u32,
	size:          vk.DeviceSize,
	mapped_memory: rawptr,
	mapped:        bool,
}

create_buffer :: proc(
	ctx: Context,
	instance_size: vk.DeviceSize,
	instance_count: u32,
	usage_flags: vk.BufferUsageFlags,
	memory_property_flags: vk.MemoryPropertyFlags,
	min_offset_alignment: vk.DeviceSize = 1,
) -> (
	buffer: Buffer,
) {
	assert(
		math.is_power_of_two(cast(int)min_offset_alignment),
		"min_offset_alignment has to be a power of 2",
	)

	alignment: vk.DeviceSize
	if min_offset_alignment > 0 {
		/*
		we want to align the instance_size to be a multiple of min_offset_alignment
		it only works on powers of 2!

		we will set the lower x bits to 0 (with 2^x = min_offset_alignment)
		min_offset_alignment == 1 -> & 11111111 (x4)
		min_offset_alignment == 2 -> & 11111111 11111111 11111111 11111110
		min_offset_alignment == 8 -> & 11111111 11111111 11111111 11111000
		...
		
		example:
		instance_size = 32
		min_offset_alignment = 2
		            v this is the instance_size + min_offset_alignment - 1
		alignment = 33 & 11111111 11111111 11111111 11111110
		          = 32 (already aligned)

		another example:
		instance_size = 34
		min_offset_alignment = 8
		alignment = 41 & 11111111 11111111 11111111 11111000
		          = ...0 00101001 & ...1 11111000
		          = ...0 00101000 = 40

		the & basically "rounds down" to the next multiple of min_offset_alignment
		we add a min_offset_alignment to the instance_size first because we want
		the result to be >= than instance_size
		*/

		alignment = (instance_size + min_offset_alignment - 1) & ~(min_offset_alignment - 1)
	} else {
		alignment = instance_size
	}

	buffer.count = instance_count
	buffer.size = alignment * cast(vk.DeviceSize)instance_count

	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = buffer.size,
		usage       = usage_flags,
		sharingMode = .EXCLUSIVE,
	}

	result := vk.CreateBuffer(ctx.device, &buffer_info, nil, &buffer.handle)
	if result != .SUCCESS {
		log.panicf("Failed to create a buffer (result: %v)", result)
	}

	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(ctx.device, buffer.handle, &mem_requirements)

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = find_memory_type_index(ctx, mem_requirements, memory_property_flags),
	}

	result = vk.AllocateMemory(ctx.device, &alloc_info, nil, &buffer.memory)
	if result != .SUCCESS {
		log.panicf("Failed to allocate the buffer memory (result: %v)", result)
	}

	result = vk.BindBufferMemory(ctx.device, buffer.handle, buffer.memory, 0)
	if result != .SUCCESS {
		log.panicf("Failed to bind the buffer memory (result: %v)", result)
	}

	return
}

destroy_buffer :: proc(ctx: Context, buffer: Buffer) {
	vk.DeviceWaitIdle(ctx.device)

	vk.DestroyBuffer(ctx.device, buffer.handle, nil)
	vk.FreeMemory(ctx.device, buffer.memory, nil)
}

map_buffer :: proc(
	ctx: Context,
	buffer: ^Buffer,
	offset: vk.DeviceSize = 0,
	loc := #caller_location,
) {
	result := vk.MapMemory(
		ctx.device,
		buffer.memory,
		offset,
		buffer.size,
		nil,
		&buffer.mapped_memory,
	)
	if result != .SUCCESS {
		log.panicf("Failed to map a buffer (result: %v)", result, location = loc)
	}

	buffer.mapped = true
}

unmap_buffer :: proc(ctx: Context, buffer: ^Buffer) {
	vk.UnmapMemory(ctx.device, buffer.memory)
	buffer.mapped = false
}

copy_to_buffer :: proc(ctx: Context, buffer: ^Buffer, data: rawptr, loc := #caller_location) {
	was_mapped := buffer.mapped

	if !was_mapped {
		map_buffer(ctx, buffer)
	}

	mem.copy_non_overlapping(buffer.mapped_memory, data, cast(int)buffer.size)

	if !was_mapped {
		unmap_buffer(ctx, buffer)
	}
}

