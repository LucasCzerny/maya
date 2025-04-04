package main

import "core:slice"

import "shared:svk"
import vk "vendor:vulkan"

Primitive_List :: struct {
	positions:   svk.Buffer,
	normals:     svk.Buffer,
	tangents:    svk.Buffer,
	tex_coords:  svk.Buffer,
	indices:     svk.Buffer,
	nr_vertices: u32,
}

create_scene_descriptor :: proc(ctx: svk.Context) -> svk.Descriptor_Set {
	bindings: [4]vk.DescriptorSetLayoutBinding

	// positions, normals, tangents, tex_coords
	for i in 0 ..< 4 {
		bindings[i] = vk.DescriptorSetLayoutBinding {
			binding         = cast(u32)i,
			descriptorType  = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.COMPUTE},
		}
	}

	return svk.create_descriptor_set(ctx, bindings[:])
}

update_scene_descriptor :: proc(
	ctx: svk.Context,
	scene_descriptor: svk.Descriptor_Set,
	primitive_list: Primitive_List,
) {
	handles := [4]vk.Buffer {
		primitive_list.positions.handle,
		primitive_list.normals.handle,
		primitive_list.tangents.handle,
		primitive_list.tex_coords.handle,
	}

	sizes := [4]vk.DeviceSize {
		primitive_list.positions.size,
		primitive_list.normals.size,
		primitive_list.tangents.size,
		primitive_list.tex_coords.size,
	}

	for i in 0 ..< 4 {
		buffer_info := vk.DescriptorBufferInfo {
			buffer = handles[i],
			offset = 0,
			range  = sizes[i],
		}

		svk.update_descriptor_set_buffer(ctx, scene_descriptor, buffer_info, 0, .STORAGE_BUFFER)
	}
}

create_primitive_list :: proc(ctx: svk.Context, models: []svk.Model) -> (list: Primitive_List) {
	nr_vertices, nr_indices: u32

	for model in models {
		scene := model.active_scene
		nr_vertices += scene.nr_vertices
		nr_indices += scene.nr_indices
	}

	list.positions = svk.create_buffer(
		ctx,
		size_of([3]f32),
		nr_vertices,
		{.STORAGE_BUFFER},
		{.HOST_COHERENT, .DEVICE_LOCAL},
	)

	list.normals = svk.create_buffer(
		ctx,
		size_of([4]f32),
		nr_vertices,
		{.STORAGE_BUFFER},
		{.HOST_COHERENT, .DEVICE_LOCAL},
	)

	list.tangents = svk.create_buffer(
		ctx,
		size_of([4]f32),
		nr_vertices,
		{.STORAGE_BUFFER},
		{.HOST_COHERENT, .DEVICE_LOCAL},
	)

	list.tex_coords = svk.create_buffer(
		ctx,
		size_of([2]f32),
		nr_vertices,
		{.STORAGE_BUFFER},
		{.HOST_COHERENT, .DEVICE_LOCAL},
	)

	list.indices = svk.create_buffer(
		ctx,
		size_of([3]u32),
		nr_indices,
		{.STORAGE_BUFFER},
		{.HOST_COHERENT, .DEVICE_LOCAL},
	)

	positions := make([]f32, nr_vertices)
	normals := make([]f32, nr_vertices)
	tangents := make([]f32, nr_vertices)
	tex_coords := make([]f32, nr_vertices)
	indices := make([]u32, nr_indices)

	nr_vertices_loaded := 0
	nr_indices_loaded := 0

	defer {
		delete(positions)
		delete(normals)
		delete(tangents)
		delete(tex_coords)
		delete(indices)
	}

	for model in models {
		scene := model.active_scene

		for node in scene.root_nodes {
			add_node(
				ctx,
				node,
				positions,
				normals,
				tangents,
				tex_coords,
				indices,
				&nr_vertices_loaded,
				&nr_indices_loaded,
			)
		}
	}

	return
}

add_node :: proc(
	ctx: svk.Context,
	node: ^svk.Node,
	positions, normals, tangents, tex_coords: []f32,
	indices: []u32,
	nr_vertices_loaded: ^int,
	nr_indices_loaded: ^int,
	parent_transform: matrix[4, 4]f32 = 1,
) {
	transform := parent_transform * node.transform

	mesh, has_mesh := node.mesh.?
	if has_mesh {
		for primitive in mesh.primitives {
			add_primitive(
				ctx,
				primitive,
				positions,
				normals,
				tangents,
				tex_coords,
				indices,
				nr_vertices_loaded,
				nr_indices_loaded,
			)
		}
	}

	for child_node in node.children {
		add_node(
			ctx,
			child_node,
			positions,
			normals,
			tangents,
			tex_coords,
			indices,
			nr_vertices_loaded,
			nr_indices_loaded,
			transform,
		)
	}
}

add_primitive :: proc(
	ctx: svk.Context,
	primitive: svk.Primitive,
	positions, normals, tangents, tex_coords: []f32,
	indices: []u32,
	nr_vertices_loaded: ^int,
	nr_indices_loaded: ^int,
) {
	target_slices := [5][]f32 {
		positions[:nr_vertices_loaded^],
		normals[:nr_vertices_loaded^],
		tangents[:nr_vertices_loaded^],
		tex_coords[:nr_vertices_loaded^],
		indices[:nr_indices_loaded^],
	}

	src_buffers := [5]svk.Buffer {
		primitive.vertex_buffers[.position],
		primitive.vertex_buffers[.normal],
		primitive.vertex_buffers[.tangent],
		primitive.vertex_buffers[.tex_coord],
		primitive.index_buffer,
	}

	nr_new_vertices: u32

	for i in 0 ..< 5 {
		buffer := src_buffers[i]
		nr_new_vertices = buffer.count

		svk.map_buffer(ctx, &buffer)

		new_data := slice.from_ptr(cast(^f32)buffer.mapped_memory, cast(int)buffer.count)
		copy_slice(target_slices[i], new_data)

		svk.unmap_buffer(ctx, &buffer)
	}

	nr_vertices_loaded^ = cast(int)nr_new_vertices

}

