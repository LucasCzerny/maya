package main

import "core:log"
import "core:slice"

import "shared:svk"

import vk "vendor:vulkan"

create_bottom_level_acceleration_structures :: proc(
	ctx: svk.Context,
	models: []svk.Model,
) -> []Acceleration_Structure {
	nr_blas := len(models)

	primitive_geometries := make([dynamic]vk.AccelerationStructureGeometryKHR)
	primitive_counts := make([dynamic]u32)

	model_geometries := make([dynamic]vk.AccelerationStructureBuildGeometryInfoKHR)
	blas_build_sizes := make([dynamic]vk.AccelerationStructureBuildSizesInfoKHR)

	nr_primitives := 0

	for model, i in models {
		start := nr_primitives

		for mesh in model.meshes {
			for primitive in mesh.primitives {
				geometry, primitive_count := create_primitive_geometry(ctx, primitive)

				append(&primitive_geometries, geometry)
				append(&primitive_counts, primitive_count)

				nr_primitives += 1
			}
		}

		end := nr_primitives

		geometry, build_size := create_model_geometry(
			ctx,
			primitive_geometries[start:end],
			primitive_counts[start:end],
		)

		append(&model_geometries, geometry)
		append(&blas_build_sizes, build_size)
	}

	max_scratch_buffer_size: u32 = 0
	for build_size in blas_build_sizes {
		scratch_buffer_size := cast(u32)build_size.buildScratchSize

		if scratch_buffer_size > max_scratch_buffer_size {
			max_scratch_buffer_size = scratch_buffer_size
		}
	}

	// TODO: scratch buffer min offset alignment
	scratch_buffer := svk.create_buffer(
		ctx,
		cast(vk.DeviceSize)max_scratch_buffer_size,
		1,
		{.SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER},
		{.DEVICE_LOCAL},
	)

	scratch_buffer_address := get_buffer_device_address(ctx, scratch_buffer)

	query_info := vk.QueryPoolCreateInfo {
		sType      = .QUERY_POOL_CREATE_INFO,
		queryType  = .ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR,
		queryCount = cast(u32)nr_blas,
	}

	query_pool: vk.QueryPool
	result := vk.CreateQueryPool(ctx.device, nil, nil, &query_pool)
	if result != nil {
		log.panicf("Failed to create the query pool (%v)", result)
	}

	// submitting everything at once could cause the pipeline to stall
	MAX_BATCH_SIZE :: 256_000_000 // = 256MB

	batch_size := 0
	batch_start_index := 0

	return_blas := make([]Acceleration_Structure, nr_blas)

	for i in 0 ..< nr_blas {
		batch_size := blas_build_sizes[i].accelerationStructureSize

		if batch_size < MAX_BATCH_SIZE && i != nr_blas - 1 {
			continue // keep accumulating
		}

		blas, blas_buffers := create_blas_batched(
			ctx,
			batch_start_index,
			i,
			blas_build_sizes[batch_start_index:i + 1],
		)

		command_buffer := svk.begin_single_time_commands(ctx)
		build_blas_batched(
			ctx,
			command_buffer,
			model_geometries[batch_start_index:i + 1],
			blas,
			primitive_counts[batch_start_index:i + 1],
			query_pool,
			scratch_buffer_address,
		)
		svk.end_single_time_commands(ctx, command_buffer)

		command_buffer = svk.begin_single_time_commands(ctx)
		compacted_blas, compacted_blas_buffers := compact_blas_batched(
			ctx,
			command_buffer,
			model_geometries[batch_start_index:i + 1],
			blas,
			query_pool,
			blas_buffers,
		)
		svk.end_single_time_commands(ctx, command_buffer)

		for i in batch_start_index ..= i {
			batch_index := i - batch_start_index

			// goodbye my lover, goodbye my friend
			vk.DestroyAccelerationStructureKHR(ctx.device, blas[i], nil)
			svk.destroy_buffer(ctx, blas_buffers[i])

			return_blas[i] = {
				handle = blas[batch_index],
				buffer = blas_buffers[batch_index],
			}
		}

		batch_start_index = i + 1
	}

	svk.destroy_buffer(ctx, scratch_buffer)

	return return_blas
}

@(private = "file")
create_primitive_geometry :: proc(
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

	primitive_count := index_buffer.count / 3

	return geometry, primitive_count
}

@(private = "file")
create_model_geometry :: proc(
	ctx: svk.Context,
	primitive_geometries: []vk.AccelerationStructureGeometryKHR,
	primitive_counts: []u32,
) -> (
	vk.AccelerationStructureBuildGeometryInfoKHR,
	vk.AccelerationStructureBuildSizesInfoKHR,
) {
	geometry_info := vk.AccelerationStructureBuildGeometryInfoKHR {
		sType         = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
		type          = .BOTTOM_LEVEL,
		flags         = {.ALLOW_COMPACTION},
		mode          = .BUILD,
		geometryCount = cast(u32)len(primitive_geometries),
		pGeometries   = raw_data(primitive_geometries),
	}

	build_sizes: vk.AccelerationStructureBuildSizesInfoKHR
	vk.GetAccelerationStructureBuildSizesKHR(
		ctx.device,
		.DEVICE,
		&geometry_info,
		raw_data(primitive_counts),
		&build_sizes,
	)

	return geometry_info, build_sizes
}

@(private = "file")
create_blas_batched :: proc(
	ctx: svk.Context,
	start_index, end_index: int,
	build_sizes: []vk.AccelerationStructureBuildSizesInfoKHR,
) -> (
	blas: []vk.AccelerationStructureKHR,
	blas_buffers: []svk.Buffer,
) {
	batch_size := end_index - start_index + 1
	blas = make([]vk.AccelerationStructureKHR, batch_size)
	blas_buffers = make([]svk.Buffer, batch_size)

	for i in start_index ..= end_index {
		blas_buffers[i] = svk.create_buffer(
			ctx,
			build_sizes[i].accelerationStructureSize,
			1,
			{.ACCELERATION_STRUCTURE_STORAGE_KHR, .SHADER_DEVICE_ADDRESS},
			{.DEVICE_LOCAL},
		)

		blas_info := vk.AccelerationStructureCreateInfoKHR {
			sType  = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
			buffer = blas_buffers[i].handle,
			size   = blas_buffers[i].size,
			type   = .BOTTOM_LEVEL,
		}

		result := vk.CreateAccelerationStructureKHR(ctx.device, &blas_info, nil, &blas[i])
		if result != .SUCCESS {
			log.panicf("Failed to create the acceleration structure with index %d (%v)", i, result)
		}
	}

	return
}

@(private = "file")
build_blas_batched :: proc(
	ctx: svk.Context,
	command_buffer: vk.CommandBuffer,
	model_geometries: []vk.AccelerationStructureBuildGeometryInfoKHR,
	blas_batch: []vk.AccelerationStructureKHR,
	primitive_counts: []u32,
	query_pool: vk.QueryPool,
	scratch_buffer_address: vk.DeviceAddress,
) {
	vk.ResetQueryPool(ctx.device, query_pool, 0, cast(u32)len(blas_batch))

	for &blas, i in blas_batch {
		build_ranges := make([]vk.AccelerationStructureBuildRangeInfoKHR, len(primitive_counts))
		for count, i in primitive_counts {
			build_ranges[i] = {
				primitiveCount = count,
			}
		}
		build_ranges_ptr := raw_data(build_ranges)

		model_geometry := &model_geometries[i]
		model_geometry.dstAccelerationStructure = blas
		model_geometry.scratchData = vk.DeviceOrHostAddressKHR {
			deviceAddress = scratch_buffer_address,
		}

		vk.CmdBuildAccelerationStructuresKHR(command_buffer, 1, model_geometry, &build_ranges_ptr)

		memory_barrier := vk.MemoryBarrier {
			sType         = .MEMORY_BARRIER,
			srcAccessMask = {.ACCELERATION_STRUCTURE_WRITE_KHR},
			dstAccessMask = {.ACCELERATION_STRUCTURE_READ_KHR},
		}
		vk.CmdPipelineBarrier(
			command_buffer,
			{.ACCELERATION_STRUCTURE_BUILD_KHR},
			{.ACCELERATION_STRUCTURE_BUILD_KHR},
			{},
			0,
			&memory_barrier,
			0,
			nil,
			0,
			nil,
		)

		vk.CmdWriteAccelerationStructuresPropertiesKHR(
			command_buffer,
			1,
			&blas,
			.ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR,
			query_pool,
			cast(u32)i,
		)
	}
}

@(private = "file")
compact_blas_batched :: proc(
	ctx: svk.Context,
	command_buffer: vk.CommandBuffer,
	model_geometries: []vk.AccelerationStructureBuildGeometryInfoKHR,
	blas_batch: []vk.AccelerationStructureKHR,
	query_pool: vk.QueryPool,
	old_blas_buffers: []svk.Buffer,
) -> (
	blas: []vk.AccelerationStructureKHR,
	blas_buffers: []svk.Buffer,
) {
	batch_size := len(blas_batch)

	compacted_sizes := make([]vk.DeviceSize, batch_size)
	result := vk.GetQueryPoolResults(
		ctx.device,
		query_pool,
		0,
		cast(u32)batch_size,
		size_of(vk.DeviceSize) * batch_size,
		raw_data(compacted_sizes),
		size_of(vk.DeviceSize),
		{.WAIT},
	)
	if result != .SUCCESS {
		log.panicf(
			"Failed to query the compacted bottom level acceleration structure sizes (result: %v)",
			result,
		)
	}

	blas_buffers = make([]svk.Buffer, batch_size)

	for old_blas, i in blas_batch {
		model_geometry := &model_geometries[i]
		model_geometry.srcAccelerationStructure = old_blas

		blas_buffers[i] = svk.create_buffer(
			ctx,
			compacted_sizes[i],
			1,
			{.ACCELERATION_STRUCTURE_STORAGE_KHR, .SHADER_DEVICE_ADDRESS},
			{.DEVICE_LOCAL},
		)

		create_info := vk.AccelerationStructureCreateInfoKHR {
			sType  = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
			buffer = blas_buffers[i].handle,
			size   = blas_buffers[i].size,
			type   = .BOTTOM_LEVEL,
		}

		vk.CreateAccelerationStructureKHR(ctx.device, &create_info, nil, &blas[i])

		copy_info := vk.CopyAccelerationStructureInfoKHR {
			sType = .COPY_ACCELERATION_STRUCTURE_INFO_KHR,
			src   = old_blas,
			dst   = blas[i],
			mode  = .COMPACT,
		}

		vk.CmdCopyAccelerationStructureKHR(command_buffer, &copy_info)
	}

	return blas, blas_buffers
}

@(private)
get_buffer_device_address :: proc(ctx: svk.Context, buffer: svk.Buffer) -> vk.DeviceAddress {
	address_info := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = buffer.handle,
	}

	return vk.GetBufferDeviceAddress(ctx.device, &address_info)
}

@(private = "file")
get_blas_device_address :: proc(
	ctx: svk.Context,
	blas: vk.AccelerationStructureKHR,
) -> vk.DeviceAddress {
	address_info := vk.AccelerationStructureDeviceAddressInfoKHR {
		sType                 = .ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
		accelerationStructure = blas,
	}

	return vk.GetAccelerationStructureDeviceAddressKHR(ctx.device, &address_info)
}
