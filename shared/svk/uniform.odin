package svk

import vk "vendor:vulkan"

Uniform :: struct {
	buffer:      Buffer,
	descriptor:  Descriptor_Set,
	stage_flags: vk.ShaderStageFlags,
}

create_uniform :: proc(
	ctx: Context,
	instance_size: vk.DeviceSize,
	instance_count: u32,
	stage_flags: vk.ShaderStageFlags,
) -> (
	uniform: Uniform,
) {
	uniform.buffer = create_buffer(
		ctx,
		instance_size,
		instance_count,
		{.UNIFORM_BUFFER},
		{.DEVICE_LOCAL, .HOST_COHERENT},
	)

	binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags      = stage_flags,
	}

	uniform.descriptor = create_descriptor_set(ctx, bindings = {binding})

	uniform.stage_flags = stage_flags

	buffer_info := vk.DescriptorBufferInfo {
		buffer = uniform.buffer.handle,
		offset = 0,
		range  = uniform.buffer.size,
	}

	update_descriptor_set(ctx, uniform.descriptor, buffer_info, 0)

	map_buffer(ctx, &uniform.buffer)

	return
}

destroy_uniform :: proc(ctx: Context, uniform: ^Uniform) {
	unmap_buffer(ctx, &uniform.buffer)

	destroy_buffer(ctx, uniform.buffer)
	vk.DestroyDescriptorSetLayout(ctx.device, uniform.descriptor.layout, nil)
}

bind_uniform :: proc(
	ctx: Context,
	uniform: Uniform,
	command_buffer: vk.CommandBuffer,
	layout: vk.PipelineLayout,
	bind_point: vk.PipelineBindPoint,
	first_set: u32,
) {
	bind_descriptor_set(ctx, uniform.descriptor, command_buffer, layout, bind_point, first_set)
}

update_uniform_buffer :: proc(
	ctx: Context,
	uniform: ^Uniform,
	data: rawptr,
	loc := #caller_location,
) {
	copy_to_buffer(ctx, &uniform.buffer, data, loc)
}

