package main

import "core:log"
import "core:slice"

import "shared:svk"
import vk "vendor:vulkan"

Primitive_List :: struct {
	positions:  svk.Buffer,
	normals:    svk.Buffer,
	tangents:   svk.Buffer,
	tex_coords: svk.Buffer,
	indices:    svk.Buffer,
}

create_scene_descriptor :: proc(ctx: svk.Context) -> svk.Descriptor_Set {
	bindings: [5]vk.DescriptorSetLayoutBinding

	// positions, normals, tangents, tex_coords, indices
	for i in 0 ..< 5 {
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
	handles := [5]vk.Buffer {
		primitive_list.positions.handle,
		primitive_list.normals.handle,
		primitive_list.tangents.handle,
		primitive_list.tex_coords.handle,
		primitive_list.indices.handle,
	}

	sizes := [5]vk.DeviceSize {
		primitive_list.positions.size,
		primitive_list.normals.size,
		primitive_list.tangents.size,
		primitive_list.tex_coords.size,
		primitive_list.indices.size,
	}

	for i in 0 ..< 5 {
		buffer_info := vk.DescriptorBufferInfo {
			buffer = handles[i],
			offset = 0,
			range  = sizes[i],
		}

		svk.update_descriptor_set_buffer(
			ctx,
			scene_descriptor,
			buffer_info,
			cast(u32)i,
			.STORAGE_BUFFER,
		)
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
		size_of([3]f32),
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
		size_of(u32),
		nr_indices,
		{.STORAGE_BUFFER},
		{.HOST_COHERENT, .DEVICE_LOCAL},
	)

	attributes := Primitive_List_Attributes {
		positions  = make([][3]f32, nr_vertices),
		normals    = make([][3]f32, nr_vertices),
		tangents   = make([][3]f32, nr_vertices),
		tex_coords = make([][2]f32, nr_vertices),
		indices    = make([]u32, nr_indices),
	}

	defer {
		delete(attributes.positions)
		delete(attributes.normals)
		delete(attributes.tangents)
		delete(attributes.tex_coords)
		delete(attributes.indices)
	}

	context.user_ptr = &attributes

	for model in models {
		scene := model.active_scene

		for node in scene.root_nodes {
			add_node(ctx, node)
		}
	}

	svk.copy_to_buffer(ctx, &list.positions, raw_data(attributes.positions))
	svk.copy_to_buffer(ctx, &list.normals, raw_data(attributes.normals))
	svk.copy_to_buffer(ctx, &list.tangents, raw_data(attributes.tangents))
	svk.copy_to_buffer(ctx, &list.tex_coords, raw_data(attributes.tex_coords))
	svk.copy_to_buffer(ctx, &list.indices, raw_data(attributes.indices))

	log.debug(attributes.positions)
	log.debug(attributes.indices)

	return
}

@(private = "file")
Primitive_List_Attributes :: struct {
	positions:          [][3]f32,
	normals:            [][3]f32,
	tangents:           [][3]f32,
	tex_coords:         [][2]f32,
	indices:            []u32,
	nr_vertices_loaded: int,
	nr_indices_loaded:  int,
}

@(private = "file")
add_node :: proc(ctx: svk.Context, node: ^svk.Node, parent_transform: matrix[4, 4]f32 = 1) {
	transform := parent_transform * node.transform

	mesh, has_mesh := node.mesh.?
	if has_mesh {
		for primitive in mesh.primitives {
			add_primitive(ctx, primitive)
		}
	}

	for child_node in node.children {
		add_node(ctx, child_node, transform)
	}
}

@(private = "file")
add_primitive :: proc(ctx: svk.Context, primitive: svk.Primitive) {
	a := cast(^Primitive_List_Attributes)context.user_ptr

	// this is embarrassing
	dst_slices := [5][]f32 {
		slice.from_ptr(
			cast(^f32)&a.positions[a.nr_vertices_loaded:][0],
			3 * (len(a.positions) - a.nr_vertices_loaded),
		),
		slice.from_ptr(
			cast(^f32)&a.normals[a.nr_vertices_loaded:][0],
			3 * (len(a.normals) - a.nr_vertices_loaded),
		),
		slice.from_ptr(
			cast(^f32)&a.tangents[a.nr_vertices_loaded:][0],
			3 * (len(a.tangents) - a.nr_vertices_loaded),
		),
		slice.from_ptr(
			cast(^f32)&a.tex_coords[a.nr_vertices_loaded:][0],
			2 * (len(a.tex_coords) - a.nr_vertices_loaded),
		),
		// kind of skuffed but u32 and f32 have the same width so why not
		slice.from_ptr(
			cast(^f32)&a.indices[a.nr_indices_loaded:][0],
			len(a.indices) - a.nr_indices_loaded,
		),
	}

	src_buffers := [5]svk.Buffer {
		primitive.vertex_buffers[.position],
		primitive.vertex_buffers[.normal],
		primitive.vertex_buffers[.tangent],
		primitive.vertex_buffers[.tex_coord],
		primitive.index_buffer,
	}

	for i in 0 ..< 5 {
		dst_slice := dst_slices[i]
		buffer := src_buffers[i]

		svk.map_buffer(ctx, &buffer)

		new_data := slice.from_ptr(cast(^f32)buffer.mapped_memory, len(dst_slice))

		copy_slice(dst_slices[i], new_data)

		svk.unmap_buffer(ctx, &buffer)
	}

	a.nr_vertices_loaded += cast(int)src_buffers[0].count
	a.nr_indices_loaded += cast(int)src_buffers[4].count
}

