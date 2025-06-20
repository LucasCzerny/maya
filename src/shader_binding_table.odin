package main

import "core:log"
import "core:mem"

import "shared:svk"

import vk "vendor:vulkan"

Shader_Binding_Table :: struct {
	buffer:             svk.Buffer,
	ray_gen_region:     vk.StridedDeviceAddressRegionKHR,
	miss_region:        vk.StridedDeviceAddressRegionKHR,
	closest_hit_region: vk.StridedDeviceAddressRegionKHR,
}

create_shader_binding_table :: proc(
	ctx: svk.Context,
	pipeline: svk.Pipeline,
	pipeline_properties: vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
) -> Shader_Binding_Table {
	handle_size := cast(vk.DeviceSize)pipeline_properties.shaderGroupHandleSize
	shader_group_alignment := cast(vk.DeviceSize)pipeline_properties.shaderGroupBaseAlignment

	handle_size_aligned := svk.align_size(
		handle_size,
		cast(vk.DeviceSize)pipeline_properties.shaderGroupHandleAlignment,
	)

	log.info(pipeline_properties.shaderGroupHandleSize)
	log.info(pipeline_properties.shaderGroupHandleAlignment)

	// i really gotta read ray tracing gems

	ray_gen_region := vk.StridedDeviceAddressRegionKHR {
		stride = svk.align_size(handle_size_aligned, shader_group_alignment),
	}
	ray_gen_region.size = ray_gen_region.stride

	miss_region := vk.StridedDeviceAddressRegionKHR {
		stride = handle_size_aligned,
		size   = svk.align_size(handle_size_aligned, shader_group_alignment), // miss_count * handle_size ...
	}

	closest_hit_region := vk.StridedDeviceAddressRegionKHR {
		stride = handle_size_aligned,
		size   = svk.align_size(handle_size_aligned, shader_group_alignment),
	}

	handles_size := 3 * cast(int)handle_size
	handle_data := make([]u8, handles_size)
	defer delete(handle_data)

	result := vk.GetRayTracingShaderGroupHandlesKHR(
		ctx.device,
		pipeline.handle,
		0,
		3,
		handles_size,
		raw_data(handle_data),
	)

	if result != .SUCCESS {
		log.panicf("Failed to get the ray tracing shader group handles (result: %v)", result)
	}

	table_size := ray_gen_region.size + miss_region.size + closest_hit_region.size
	table_buffer := svk.create_buffer(
		ctx,
		table_size,
		1,
		{.TRANSFER_SRC, .SHADER_DEVICE_ADDRESS, .SHADER_BINDING_TABLE_KHR},
		{.HOST_COHERENT, .HOST_VISIBLE},
	)

	table_address_info := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = table_buffer.handle,
	}

	table_device_address := vk.GetBufferDeviceAddress(ctx.device, &table_address_info)
	ray_gen_region.deviceAddress = table_device_address

	// vk.DeviceSize and vk.DeviceAddress are both u64's
	offset := cast(vk.DeviceAddress)ray_gen_region.size
	miss_region.deviceAddress = table_device_address + offset

	offset += cast(vk.DeviceAddress)miss_region.size
	closest_hit_region.deviceAddress = table_device_address + offset

	svk.map_buffer(ctx, &table_buffer)

	handle_ptr := cast(^u8)table_buffer.mapped_memory
	mem.copy_non_overlapping(
		handle_ptr,
		raw_data(get_handle(handle_data, handle_size, 0)),
		cast(int)handle_size,
	)

	handle_ptr = mem.ptr_offset(handle_ptr, cast(int)ray_gen_region.stride)
	mem.copy_non_overlapping(
		handle_ptr,
		raw_data(get_handle(handle_data, handle_size, 1)),
		cast(int)handle_size,
	)

	handle_ptr = mem.ptr_offset(handle_ptr, cast(int)miss_region.stride)
	mem.copy_non_overlapping(
		handle_ptr,
		raw_data(get_handle(handle_data, handle_size, 2)),
		cast(int)handle_size,
	)

	svk.unmap_buffer(ctx, &table_buffer)

	return {
		buffer = table_buffer,
		ray_gen_region = ray_gen_region,
		miss_region = miss_region,
		closest_hit_region = closest_hit_region,
	}
}

@(private = "file")
get_handle :: proc(handle_data: []u8, handle_size: vk.DeviceSize, index: int) -> []u8 {
	start := cast(vk.DeviceSize)index * handle_size
	end := start + handle_size

	return handle_data[start:end]
}

