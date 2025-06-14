package main

import "core:log"

import "shared:svk"

import vk "vendor:vulkan"

create_top_level_acceleration_structure :: proc(
	ctx: svk.Context,
	model_instances: []Model_Instance,
) -> Acceleration_Structure {
	instances := make([]vk.AccelerationStructureInstanceKHR, len(model_instances))
	for model, i in model_instances {
		instances[0] = {
			transform = vk.TransformMatrixKHR {
				mat = {{2.0, 0.0, 0.0, 0.0}, {0.0, 2.0, 0.0, 0.0}, {0.0, 0.0, 2.0, 0.0}},
			},
			instanceCustomIndex = cast(u32)i,
			mask = 0xFF,
			// TODO: select with hit group to use
			// instanceShaderBindingTableRecordOffset = ,
			accelerationStructureReference = cast(u64)get_buffer_device_address(
				ctx,
				model.blas.buffer,
			),
		}
	}

	instances_buffer := svk.create_buffer(
		ctx,
		size_of(vk.AccelerationStructureInstanceKHR),
		cast(u32)len(instances),
		{.SHADER_DEVICE_ADDRESS, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
		{.DEVICE_LOCAL},
	)

	instances_buffer_addr := get_buffer_device_address(ctx, instances_buffer)
	instances_struct := vk.AccelerationStructureGeometryInstancesDataKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
		data = vk.DeviceOrHostAddressConstKHR{deviceAddress = instances_buffer_addr},
	}

	geometry := vk.AccelerationStructureGeometryKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
		geometryType = .INSTANCES,
		geometry = vk.AccelerationStructureGeometryDataKHR{instances = instances_struct},
		flags = {.OPAQUE},
	}

	command_buffer := svk.begin_single_time_commands(ctx)

	tlas, tlas_buffer := build_tlas(ctx, command_buffer, geometry, cast(u32)len(instances))

	svk.end_single_time_commands(ctx, command_buffer)

	svk.destroy_buffer(ctx, instances_buffer)

	return Acceleration_Structure{handle = tlas, buffer = tlas_buffer}
}

@(private = "file")
build_tlas :: proc(
	ctx: svk.Context,
	command_buffer: vk.CommandBuffer,
	geometry: vk.AccelerationStructureGeometryKHR,
	nr_instances: u32,
) -> (
	tlas: vk.AccelerationStructureKHR,
	tlas_buffer: svk.Buffer,
) {
	geometry := geometry
	nr_instances := nr_instances

	build_info := vk.AccelerationStructureBuildGeometryInfoKHR {
		sType                    = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
		type                     = .TOP_LEVEL,
		mode                     = .BUILD,
		dstAccelerationStructure = tlas,
		geometryCount            = 1,
		pGeometries              = &geometry,
	}

	size_info := vk.AccelerationStructureBuildSizesInfoKHR {
		sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR,
	}

	vk.GetAccelerationStructureBuildSizesKHR(
		ctx.device,
		.DEVICE,
		&build_info,
		&nr_instances,
		&size_info,
	)

	tlas_buffer = svk.create_buffer(
		ctx,
		size_info.accelerationStructureSize,
		1,
		{.SHADER_DEVICE_ADDRESS, .ACCELERATION_STRUCTURE_STORAGE_KHR},
		{.DEVICE_LOCAL},
	)

	create_info := vk.AccelerationStructureCreateInfoKHR {
		sType         = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
		buffer        = tlas_buffer.handle,
		size          = tlas_buffer.size,
		type          = .TOP_LEVEL,
		deviceAddress = get_buffer_device_address(ctx, tlas_buffer),
	}

	result := vk.CreateAccelerationStructureKHR(ctx.device, &create_info, nil, &tlas)
	if result != .SUCCESS {
		log.panicf("Failed to create the top level acceleration structure (result: %v)", result)
	}

	scratch_buffer := svk.create_buffer(
		ctx,
		size_info.buildScratchSize,
		1,
		{.SHADER_DEVICE_ADDRESS, .ACCELERATION_STRUCTURE_STORAGE_KHR},
		{.DEVICE_LOCAL},
	)

	build_info.scratchData = vk.DeviceOrHostAddressKHR {
		deviceAddress = get_buffer_device_address(ctx, scratch_buffer),
	}

	build_range_info := vk.AccelerationStructureBuildRangeInfoKHR {
		primitiveCount = nr_instances,
	}
	build_range_info_ptr := cast([^]vk.AccelerationStructureBuildRangeInfoKHR)&build_range_info

	vk.CmdBuildAccelerationStructuresKHR(command_buffer, 1, &build_info, &build_range_info_ptr)

	svk.destroy_buffer(ctx, scratch_buffer)

	return tlas, tlas_buffer
}

