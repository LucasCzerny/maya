package main

import "core:log"
import "core:slice"

import "shared:svk"

import vk "vendor:vulkan"

Bottom_Level_Acceleration_Structure :: struct {
	geometry: vk.AccelerationStructureGeometryKHR,
	offset:   vk.AccelerationStructureBuildRangeInfoKHR,
}

create_acceleration_structure :: proc(
	ctx: svk.Context,
	models: []svk.Model,
) -> Bottom_Level_Acceleration_Structure {

	all_blas := make([dynamic]Bottom_Level_Acceleration_Structure)

	for model in models {
		for mesh in model.meshes {
			for primitive in mesh.primitives {
				append(&all_blas, create_primitive_blas(ctx, primitive))
			}
		}
	}

	command_buffer := svk.begin_single_time_commands(ctx)

	for blas in all_blas {
		vk.CmdBuildAccelerationStructuresKHR(command_buffer)
	}

	svk.end_single_time_commands(ctx, command_buffer)

	pool_info := vk.QueryPoolCreateInfo {
		sType      = .QUERY_POOL_CREATE_INFO,
		queryType  = .ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR,
		queryCount = cast(u32)len(all_blas),
	}

	query_pool: vk.QueryPool
	result := vk.CreateQueryPool(ctx.device, &pool_info, nil, &query_pool)
	if result != .SUCCESS {
		log.panicf("Failed to create the query pool (%v)", result)
	}

	return {}
}

@(private = "file")
create_primitive_blas :: proc(
	ctx: svk.Context,
	primitive: svk.Primitive,
) -> (
	blas: Bottom_Level_Acceleration_Structure,
) {
	vertex_buffer := primitive.vertex_buffers[.position]
	index_buffer := primitive.index_buffer

	address_info := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = vertex_buffer.handle,
	}
	vertex_buffer_address := vk.GetBufferDeviceAddress(ctx.device, &address_info)

	address_info.buffer = index_buffer.handle
	index_buffer_address := vk.GetBufferDeviceAddress(ctx.device, &address_info)

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

	blas.geometry = vk.AccelerationStructureGeometryKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
		geometryType = .TRIANGLES,
		flags = {.OPAQUE},
		geometry = vk.AccelerationStructureGeometryDataKHR{triangles = triangles},
	}

	blas.offset = vk.AccelerationStructureBuildRangeInfoKHR {
		primitiveCount  = index_buffer.count / 3,
		primitiveOffset = 0,
		firstVertex     = 0,
		transformOffset = 0,
	}

	geometry_info := vk.AccelerationStructureBuildGeometryInfoKHR {
		sType                    = StructureType,
		pNext                    = rawptr,
		type                     = AccelerationStructureTypeKHR,
		flags                    = BuildAccelerationStructureFlagsKHR,
		mode                     = BuildAccelerationStructureModeKHR,
		srcAccelerationStructure = AccelerationStructureKHR,
		dstAccelerationStructure = AccelerationStructureKHR,
		geometryCount            = u32,
		pGeometries              = [^]AccelerationStructureGeometryKHR,
		ppGeometries             = ^[^]AccelerationStructureGeometryKHR,
		scratchData              = DeviceOrHostAddressKHR,
	}

	return
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

