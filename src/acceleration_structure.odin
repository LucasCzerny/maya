package main

import "core:log"
import "core:slice"

import "shared:svk"

import vk "vendor:vulkan"

Bottom_Level_Acceleration_Structure :: struct {
	handle:         vk.AccelerationStructureKHR,
	buffer:         svk.Buffer,
	scratch_buffer: svk.Buffer,
}

create_bottom_level_acceleration_structure :: proc(
	ctx: svk.Context,
	models: []svk.Model,
) -> []Bottom_Level_Acceleration_Structure {
	all_blas := make([]Bottom_Level_Acceleration_Structure, len(models))

	for model, i in models {
		geometries := make([dynamic]vk.AccelerationStructureGeometryKHR)
		primitive_counts := make([dynamic]u32)

		for mesh in model.meshes {
			for primitive in mesh.primitives {
				geometry, primitive_count := create_primitive_blas(ctx, primitive)

				append(&geometries, geometry)
				append(&primitive_counts, primitive_count)
			}
		}

		all_blas[i] = create_acceleration_structure_for_model(
			ctx,
			geometries[:],
			primitive_counts[:],
			query_pool,
		)
	}

	for bla in all_blas {
	}

	return all_blas
}

destroy_acceleration_structure :: proc(
	ctx: svk.Context,
	blas: Bottom_Level_Acceleration_Structure,
) {
	vk.DestroyAccelerationStructureKHR(ctx.device, blas.handle, nil)
	svk.destroy_buffer(ctx, blas.buffer)
	svk.destroy_buffer(ctx, blas.scratch_buffer)
}

@(private = "file")
create_primitive_blas :: proc(
	ctx: svk.Context,
	primitive: svk.Primitive,
) -> (
	vk.AccelerationStructureGeometryKHR,
	u32,
) {
	vertex_buffer := primitive.vertex_buffers[.position]
	index_buffer := primitive.index_buffer

	vertex_buffer_address := get_buffer_device_address(ctx, vertex_buffer)
	index_buffer_address := get_buffer_device_address(ctx, index_buffer)

	// TODO
	transform := vk.TransformMatrixKHR {
		mat = {{5, 0, 0, 0}, {0, 5, 0, 0}, {0, 0, 5, 0}},
	}

	triangles := vk.AccelerationStructureGeometryTrianglesDataKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
		vertexFormat = .R32G32B32_SFLOAT,
		vertexData = vk.DeviceOrHostAddressConstKHR{deviceAddress = vertex_buffer_address},
		vertexStride = size_of([3]f32),
		maxVertex = vertex_buffer.count - 1,
		indexType = .UINT32,
		indexData = vk.DeviceOrHostAddressConstKHR{deviceAddress = index_buffer_address},
	}

	geometry := vk.AccelerationStructureGeometryKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
		geometryType = .TRIANGLES,
		geometry = vk.AccelerationStructureGeometryDataKHR{triangles = triangles},
		flags = {.OPAQUE},
	}

	primitiveCount := index_buffer.count / 3

	return geometry, primitiveCount
}

@(private = "file")
create_acceleration_structure_for_model :: proc(
	ctx: svk.Context,
	geometries: []vk.AccelerationStructureGeometryKHR,
	primitive_counts: []u32,
) -> Bottom_Level_Acceleration_Structure {
	blas: vk.AccelerationStructureKHR

	geometry_info := vk.AccelerationStructureBuildGeometryInfoKHR {
		sType                    = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
		type                     = .BOTTOM_LEVEL,
		flags                    = {.ALLOW_COMPACTION},
		mode                     = .BUILD,
		dstAccelerationStructure = blas,
		geometryCount            = cast(u32)len(geometries),
		pGeometries              = raw_data(geometries),
	}

	build_sizes: vk.AccelerationStructureBuildSizesInfoKHR
	vk.GetAccelerationStructureBuildSizesKHR(
		ctx.device,
		.DEVICE,
		&geometry_info,
		raw_data(primitive_counts),
		&build_sizes,
	)

	blas_buffer := svk.create_buffer(
		ctx,
		build_sizes.accelerationStructureSize,
		1,
		{.ACCELERATION_STRUCTURE_STORAGE_KHR, .SHADER_DEVICE_ADDRESS},
		{.DEVICE_LOCAL},
	)

	scratch_buffer := svk.create_buffer(
		ctx,
		build_sizes.buildScratchSize,
		1,
		{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		{.DEVICE_LOCAL},
	)

	as_info := vk.AccelerationStructureCreateInfoKHR {
		sType  = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
		buffer = blas_buffer.handle,
		size   = blas_buffer.size,
		type   = .BOTTOM_LEVEL,
	}

	result := vk.CreateAccelerationStructureKHR(ctx.device, &as_info, nil, &blas)
	if result != .SUCCESS {
		log.panicf("Failed to create the acceleration structure (%v)", result)
	}

	blas_buffer_address := get_buffer_device_address(ctx, blas_buffer)
	scratch_buffer_address := get_buffer_device_address(ctx, scratch_buffer)

	geometry_info.scratchData.deviceAddress = scratch_buffer_address

	command_buffer := svk.begin_single_time_commands(ctx)

	build_ranges := make([]vk.AccelerationStructureBuildRangeInfoKHR, len(primitive_counts))
	for count, i in primitive_counts {
		build_ranges[i] = {
			primitiveCount = count,
		}
	}

	build_ranges_ptr := raw_data(build_ranges)
	vk.CmdBuildAccelerationStructuresKHR(command_buffer, 1, &geometry_info, &build_ranges_ptr)

	svk.end_single_time_commands(ctx, command_buffer)

	// for compaction
	query_info := vk.QueryPoolCreateInfo {
		sType      = .QUERY_POOL_CREATE_INFO,
		queryType  = .ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR,
		queryCount = 1,
	}

	query_pool: vk.QueryPool
	result = vk.CreateQueryPool(ctx.device, nil, nil, &query_pool)
	if result != nil {
		log.panicf("Failed to create the query pool (%v)", result)
	}

	compacted_size: vk.DeviceSize
	vk.GetQueryPoolResults(
		ctx.device,
		query_pool,
		0,
		1,
		size_of(vk.DeviceSize),
		&compacted_size,
		size_of(vk.DeviceSize),
		{.WAIT},
	)

	compacted_blas_buffer := svk.create_buffer(
		ctx,
		build_sizes.accelerationStructureSize,
		1,
		{.ACCELERATION_STRUCTURE_STORAGE_KHR, .SHADER_DEVICE_ADDRESS},
		{.DEVICE_LOCAL},
	)

	as_info.buffer = compacted_blas_buffer.handle
	as_info.size = compacted_size

	compacted_blas: vk.AccelerationStructureKHR
	result = vk.CreateAccelerationStructureKHR(ctx.device, &as_info, nil, &blas)
	if result != .SUCCESS {
		log.panicf(
			"Failed to create the compacted bottom level acceleration structure (%v)",
			result,
		)
	}

	command_buffer = svk.begin_single_time_commands(ctx)

	geometry_info.dstAccelerationStructure = compacted_blas
	vk.CmdBuildAccelerationStructuresKHR(command_buffer, 1, &geometry_info, &build_ranges_ptr)

	compact_info := vk.CopyAccelerationStructureInfoKHR {
		sType = .COPY_ACCELERATION_STRUCTURE_INFO_KHR,
		src   = blas,
		dst   = compacted_blas,
		mode  = .COMPACT,
	}

	vk.CmdCopyAccelerationStructureKHR(command_buffer, &compact_info)

	svk.end_single_time_commands(ctx, command_buffer)

	return Bottom_Level_Acceleration_Structure {
		handle = compacted_blas,
		buffer = blas_buffer,
		scratch_buffer = scratch_buffer,
	}
}

@(private = "file")
get_buffer_device_address :: proc(ctx: svk.Context, buffer: svk.Buffer) -> vk.DeviceAddress {
	address_info := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = buffer.handle,
	}

	return vk.GetBufferDeviceAddress(ctx.device, &address_info)
}

// @(private = "file")
// create_bounding_box :: proc(ctx: svk.Context, primitive: svk.Primitive) -> svk.Buffer {
// 	vertex_buffer := &primitive.vertex_buffers[.position]

// 	svk.map_buffer(ctx, vertex_buffer)
// 	positions := slice.from_ptr(
// 		cast(^[3]f32)vertex_buffer.mapped_memory,
// 		cast(int)vertex_buffer.count,
// 	)

// 	for position in positions {

// 	}

// 	svk.unmap_buffer(ctx, vertex_buffer)

// 	return {}
// }

