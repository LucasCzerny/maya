package svk

// TODO: use one binding for all textures (probably)

import "base:builtin"
import "core:log"
import "core:math/linalg"
import "core:mem"
import "core:path/filepath"

import "vendor:cgltf"
import vk "vendor:vulkan"

Model_Attribute :: enum u32 {
	invalid,
	position,
	normal,
	tangent,
	tex_coord,
	color,
	joints,
	weights,
	custom,
}

Model :: struct {
	scenes:       []Scene,
	nodes:        []Node,
	meshes:       []Mesh,
	materials:    []Material,
	active_scene: ^Scene,
}

Scene :: struct {
	nr_vertices: u32,
	nr_indices:  u32,
	root_nodes:  []^Node,
}

// some nodes are just for structure and don't have a mesh
Node :: struct {
	mesh:      Maybe(^Mesh),
	transform: matrix[4, 4]f32,
	children:  []^Node,
	_loaded:   bool,
}

Mesh :: struct {
	nr_vertices: u32,
	nr_indices:  u32,
	primitives:  []Primitive,
}

Primitive :: struct {
	vertex_buffers: map[Model_Attribute]Buffer,
	index_buffer:   Buffer,
	index_type:     vk.IndexType,
	material:       ^Material,
}

Model_Loading_Error :: enum {
	none,
	base_color_not_available,
	pbr_metallic_roughness_not_available,
	pbr_specular_glossiness_not_available,
	clearcoat_not_available,
	transmission_not_available,
	volume_not_available,
	ior_not_available,
	specular_not_available,
	sheen_not_available,
	emissive_strength_not_available,
	iridescence_not_available,
	anisotropy_not_available,
	dispersion_not_available,
}

// the descriptor will contain all of the textures in the same order as in the definition of the Model_Texture_Type struct
// for more info on the enums, see model_textures.odin
Material :: struct {
	descriptor:   Descriptor_Set,
	textures:     [dynamic]Image,
	samplers:     [dynamic]vk.Sampler,
	//
	data_scalar:  map[Model_Texture_Data_Scalar]f32,
	data_vec3:    map[Model_Texture_Data_Vec3][3]f32,
	data_vec4:    map[Model_Texture_Data_Vec4][4]f32,
	//
	alpha_mode:   Alpha_Mode,
	alpha_cutoff: f32,
	double_sided: b32,
}

// in the model loading code, all of the structs with the src_ prefix have a svk version too
// the prefix is there to make them more distinct

load_model :: proc(
	ctx: Context,
	path: cstring,
	attributes: bit_set[Model_Attribute],
	texture_types: bit_set[Model_Texture_Type],
	vertex_buffer_usage: vk.BufferUsageFlags = {.VERTEX_BUFFER},
	index_buffer_usage: vk.BufferUsageFlags = {.INDEX_BUFFER},
	texture_stage_flags: vk.ShaderStageFlags = {.FRAGMENT},
) -> (
	model: Model,
	err: Model_Loading_Error,
) {
	options: cgltf.options

	data, result := cgltf.parse_file(options, path)
	if result != .success {
		log.panicf("Failed to parse the %s file (result: %v)", path, result)
	}

	result = cgltf.load_buffers(options, data, path)
	if result != .success {
		log.panicf("Failed to load the buffers for %s (result: %v)", path, result)
	}

	defer cgltf.free(data)

	model_loading_options := Model_Loading_Options {
		model_dir           = filepath.dir(cast(string)path),
		attributes          = attributes,
		texture_types       = texture_types,
		vertex_buffer_usage = vertex_buffer_usage,
		index_buffer_usage  = index_buffer_usage,
		texture_stage_flags = texture_stage_flags,
		anisotropy_enabled  = ctx.anisotropy_enabled,
	}

	if ctx.anisotropy_enabled {
		properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(ctx.physical_device, &properties)

		model_loading_options.max_sampler_anisotropy = properties.limits.maxSamplerAnisotropy
	}

	// to avoid having to pass all of this shit around everywhere
	context.user_ptr = &model_loading_options

	model.materials = make([]Material, len(data.materials))
	for src_material, i in data.materials {
		model.materials[i] = load_material(ctx, data, src_material) or_return
	}

	model.meshes = make([]Mesh, len(data.meshes))
	for src_mesh, i in data.meshes {
		model.meshes[i] = load_mesh(ctx, &model, data, src_mesh) // or_return (TODO)
	}

	model.scenes = make([]Scene, len(data.scenes))
	model.nodes = make([]Node, len(data.nodes))
	for src_scene, i in data.scenes {
		model.scenes[i] = load_scene(&model, data, src_scene)
	}

	scene_index := cgltf.scene_index(data, data.scene)
	model.active_scene = &model.scenes[scene_index]

	return model, nil
}

@(private = "file")
Model_Loading_Options :: struct {
	model_dir:              string,
	attributes:             bit_set[Model_Attribute],
	texture_types:          bit_set[Model_Texture_Type],
	vertex_buffer_usage:    vk.BufferUsageFlags,
	index_buffer_usage:     vk.BufferUsageFlags,
	texture_stage_flags:    vk.ShaderStageFlags,
	anisotropy_enabled:     bool,
	max_sampler_anisotropy: f32,
	nr_vertices_scene:      u32,
	nr_indices_scene:       u32,
}

@(private = "file")
load_mesh :: proc(
	ctx: Context,
	model: ^Model,
	data: ^cgltf.data,
	src_mesh: cgltf.mesh,
) -> (
	mesh: Mesh,
) {
	mesh.primitives = make([]Primitive, len(src_mesh.primitives))

	for src_primitive, i in src_mesh.primitives {
		nr_vertices, nr_indices: u32

		primitive := &mesh.primitives[i]
		primitive^ = load_primitive(ctx, model, data, src_primitive)

		mesh.nr_vertices += primitive.vertex_buffers[.position].count
		mesh.nr_indices += primitive.index_buffer.count
	}

	return mesh
}

@(private = "file")
load_primitive :: proc(
	ctx: Context,
	model: ^Model,
	data: ^cgltf.data,
	src_primitive: cgltf.primitive,
) -> (
	primitive: Primitive,
) {
	options := cast(^Model_Loading_Options)context.user_ptr

	primitive.vertex_buffers = make(map[Model_Attribute]Buffer, len(src_primitive.attributes))

	for attribute in src_primitive.attributes {
		attribute_type := transmute(Model_Attribute)attribute.type

		if attribute_type not_in options.attributes {
			continue
		}

		accessor := attribute.data
		stride := accessor.stride > 0 ? accessor.stride : get_accessor_type_size(accessor.type)

		primitive.vertex_buffers[attribute_type] = create_buffer(
			ctx,
			cast(vk.DeviceSize)stride,
			cast(u32)accessor.count,
			options.vertex_buffer_usage,
			{.HOST_COHERENT, .DEVICE_LOCAL},
		)

		copy_accessor_data_to_buffer(ctx, accessor, &primitive.vertex_buffers[attribute_type])
	}

	accessor := src_primitive.indices
	stride, type := get_index_size_and_vk_type(accessor.component_type)
	primitive.index_type = type

	primitive.index_buffer = create_buffer(
		ctx,
		cast(vk.DeviceSize)stride,
		cast(u32)accessor.count,
		options.index_buffer_usage,
		{.HOST_COHERENT, .DEVICE_LOCAL},
	)

	copy_accessor_data_to_buffer(ctx, accessor, &primitive.index_buffer)

	material_index := cgltf.material_index(data, src_primitive.material)
	primitive.material = &model.materials[material_index]

	return
}

@(private = "file")
load_material :: proc(
	ctx: Context,
	data: ^cgltf.data,
	src_material: cgltf.material,
) -> (
	material: Material,
	err: Model_Loading_Error,
) {
	options := cast(^Model_Loading_Options)context.user_ptr

	material.textures = make([dynamic]Image)
	material.samplers = make([dynamic]vk.Sampler)

	pbr_mr := src_material.pbr_metallic_roughness
	pbr_sg := src_material.pbr_specular_glossiness

	for type in options.texture_types {
		switch (type) {
		case .base_color:
			if !src_material.has_pbr_metallic_roughness &&
			   !src_material.has_pbr_specular_glossiness {
				return {}, .base_color_not_available
			}

			src_texture_view :=
				src_material.has_pbr_metallic_roughness ? pbr_mr.base_color_texture : pbr_sg.diffuse_texture
			append(&material.textures, load_texture(ctx, src_texture_view, true))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_vec4[.base_color_factor] = pbr_mr.base_color_factor

		case .pbr_metallic_roughness:
			if !src_material.has_pbr_metallic_roughness {
				return {}, .pbr_metallic_roughness_not_available
			}

			src_texture_view := pbr_mr.metallic_roughness_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.metallic_factor] = pbr_mr.metallic_factor
			material.data_scalar[.roughness_factor] = pbr_mr.roughness_factor

		case .pbr_specular_glossiness:
			if !src_material.has_pbr_metallic_roughness {
				return {}, .pbr_specular_glossiness_not_available
			}

			src_texture_view := pbr_sg.specular_glossiness_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_vec3[.specular_factor] = pbr_sg.specular_factor
			material.data_scalar[.glossiness_factor] = pbr_sg.glossiness_factor

		case .clearcoat:
			if !src_material.has_clearcoat {
				return {}, .clearcoat_not_available
			}

			c := src_material.clearcoat

			src_texture_view := c.clearcoat_roughness_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			src_texture_view = c.clearcoat_normal_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.clearcoat_factor] = c.clearcoat_factor
			material.data_scalar[.clearcoat_roughness_factor] = c.clearcoat_roughness_factor

		case .transmission:
			if !src_material.has_transmission {
				return {}, .transmission_not_available
			}

			t := src_material.transmission

			src_texture_view := t.transmission_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.transmission_factor] = t.transmission_factor

		case .volume:
			if !src_material.has_volume {
				return {}, .volume_not_available
			}

			v := src_material.volume

			src_texture_view := v.thickness_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.thickness_factor] = v.thickness_factor
			material.data_vec3[.attenuation_color] = v.attenuation_color
			material.data_scalar[.attenuation_distance] = v.attenuation_distance

		case .ior:
			if !src_material.has_ior {
				return {}, .ior_not_available
			}

			i := src_material.ior
			material.data_scalar[.ior] = i.ior

		case .specular:
			if !src_material.has_specular {
				return {}, .specular_not_available
			}

			s := src_material.specular

			src_texture_view := s.specular_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_vec3[.specular_color_factor] = s.specular_color_factor
			material.data_scalar[.specular_factor] = s.specular_factor

		case .sheen:
			if !src_material.has_sheen {
				return {}, .sheen_not_available
			}

			s := src_material.sheen

			src_texture_view := s.sheen_color_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			src_texture_view = s.sheen_roughness_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_vec3[.sheen_color_factor] = s.sheen_color_factor
			material.data_scalar[.sheen_roughness_factor] = s.sheen_roughness_factor

		case .emissive_strength:
			if !src_material.has_emissive_strength {
				return {}, .emissive_strength_not_available
			}

			e := src_material.emissive_strength
			material.data_scalar[.emissive_strength] = e.emissive_strength

		case .iridescence:
			if !src_material.has_iridescence {
				return {}, .iridescence_not_available
			}

			i := src_material.iridescence

			src_texture_view := i.iridescence_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.iridescence_factor] = i.iridescence_factor
			material.data_scalar[.iridescence_ior] = i.iridescence_ior
			material.data_scalar[.iridescence_thickness_min] = i.iridescence_thickness_min
			material.data_scalar[.iridescence_thickness_max] = i.iridescence_thickness_max

		case .anisotropy:
			if !src_material.has_anisotropy {
				return {}, .anisotropy_not_available
			}

			a := src_material.anisotropy

			src_texture_view := a.anisotropy_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.anisotropy_strength] = a.anisotropy_strength
			material.data_scalar[.anisotropy_rotation] = a.anisotropy_rotation

		case .dispersion:
			if !src_material.has_dispersion {
				return {}, .dispersion_not_available
			}

			d := src_material.dispersion
			material.data_scalar[.dispersion] = d.dispersion
		}
	}

	bindings := make([]vk.DescriptorSetLayoutBinding, len(material.textures))

	for i in 0 ..< len(material.textures) {
		bindings[i] = vk.DescriptorSetLayoutBinding {
			binding         = cast(u32)i,
			descriptorType  = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags      = options.texture_stage_flags,
		}
	}

	material.descriptor = create_descriptor_set(ctx, bindings)

	for sampler, i in material.samplers {
		image_info := vk.DescriptorImageInfo {
			sampler     = sampler,
			imageView   = material.textures[i].view,
			imageLayout = material.textures[i].layout,
		}

		update_descriptor_set(ctx, material.descriptor, image_info, cast(u32)i)
	}

	return
}

@(private = "file")
load_texture :: proc(ctx: Context, src_texture_view: cgltf.texture_view, srgb: bool) -> Image {
	options := cast(^Model_Loading_Options)context.user_ptr

	src_texture := src_texture_view.texture
	src_image := src_texture.image_

	is_embedded := src_image.uri == ""

	if is_embedded {
		src_buffer_view := src_image.buffer_view
		src_buffer := src_buffer_view.buffer

		data_ptr := mem.ptr_offset(cast([^]u8)src_buffer.data, src_buffer_view.offset)

		return load_image_from_bytes(ctx, data_ptr[:src_buffer_view.size], srgb)
	} else {
		full_path := filepath.join({options.model_dir, cast(string)src_image.uri})
		log.infof("Loading %s", full_path)
		return load_image_from_file(ctx, full_path, srgb)
	}
}

@(private = "file")
create_sampler :: proc(
	ctx: Context,
	src_texture_view: cgltf.texture_view,
) -> (
	sampler: vk.Sampler,
) {
	options := cast(^Model_Loading_Options)context.user_ptr

	src_sampler := src_texture_view.texture.sampler
	if src_sampler == nil {
		return create_default_sampler(ctx)
	}

	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = filter_cgltf_to_vk(src_sampler.mag_filter),
		minFilter               = filter_cgltf_to_vk(src_sampler.min_filter),
		mipmapMode              = mipmap_mode_cgltf_to_vk(src_sampler.min_filter),
		addressModeU            = wrap_mode_cgltf_to_vk(src_sampler.wrap_s),
		addressModeV            = wrap_mode_cgltf_to_vk(src_sampler.wrap_t),
		addressModeW            = .CLAMP_TO_EDGE, // gltf spec doesn't specify this
		mipLodBias              = 0,
		anisotropyEnable        = cast(b32)options.anisotropy_enabled,
		maxAnisotropy           = options.max_sampler_anisotropy,
		compareEnable           = false,
		compareOp               = .NEVER,
		// minLod                  = f32,
		// maxLod                  = f32,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
	}

	result := vk.CreateSampler(ctx.device, &sampler_info, nil, &sampler)
	if result != .SUCCESS {
		log.panicf("Failed to create a texture image sampler (result: %v)", result)
	}

	return
}

@(private = "file")
create_default_sampler :: proc(ctx: Context) -> (sampler: vk.Sampler) {
	options := cast(^Model_Loading_Options)context.user_ptr

	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		mipmapMode              = .LINEAR,
		addressModeU            = .CLAMP_TO_EDGE,
		addressModeV            = .CLAMP_TO_EDGE,
		addressModeW            = .CLAMP_TO_EDGE,
		mipLodBias              = 0,
		anisotropyEnable        = cast(b32)options.anisotropy_enabled,
		maxAnisotropy           = options.max_sampler_anisotropy,
		compareEnable           = false,
		compareOp               = .NEVER,
		// minLod                  = f32,
		// maxLod                  = f32,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
	}

	result := vk.CreateSampler(ctx.device, &sampler_info, nil, &sampler)
	if result != .SUCCESS {
		log.panicf("Failed to create a texture image sampler (result: %v)", result)
	}

	return
}

@(private = "file")
load_scene :: proc(model: ^Model, data: ^cgltf.data, src_scene: cgltf.scene) -> (scene: Scene) {
	options := cast(^Model_Loading_Options)context.user_ptr

	scene.root_nodes = make([]^Node, len(src_scene.nodes))
	options.nr_vertices_scene = 0
	options.nr_indices_scene = 0

	for root_node, i in src_scene.nodes {
		scene.root_nodes[i] = load_node(model, data, root_node)
	}

	scene.nr_vertices = options.nr_vertices_scene
	scene.nr_indiecs = options.nr_indices_scene

	return scene
}

@(private = "file")
load_node :: proc(
	model: ^Model,
	data: ^cgltf.data,
	src_node: ^cgltf.node,
	parent_transform: matrix[4, 4]f32 = 1,
) -> (
	node: ^Node,
) {
	options := cast(^Model_Loading_Options)context.user_ptr

	node_index := cgltf.node_index(data, src_node)
	node = &model.nodes[node_index]

	if node._loaded {
		return node
	}

	if src_node.mesh != nil {
		mesh_index := cgltf.mesh_index(data, src_node.mesh)
		mesh := &model.meshes[mesh_index]

		node.mesh = mesh
		options.nr_vertices_scene += mesh.nr_vertices
		options.nr_indices_scene += mesh.nr_indices
	}

	node_transform: matrix[4, 4]f32 = 1

	if src_node.has_translation {
		node_transform *= linalg.matrix4_translate(src_node.translation)
	}
	if src_node.has_rotation {
		r := src_node.rotation
		quat: quaternion128 = builtin.quaternion(w = r.w, x = r.x, y = r.y, z = r.z)
		node_transform *= linalg.matrix4_from_quaternion(quat)
	}
	if src_node.has_scale {
		node_transform *= linalg.matrix4_scale(src_node.scale)
	}

	node.transform = parent_transform * node_transform

	node._loaded = true

	node.children = make([]^Node, len(src_node.children))
	for child_node, i in src_node.children {
		node.children[i] = load_node(model, data, child_node, node.transform)
	}

	return
}

// utility

@(private = "file")
copy_accessor_data_to_buffer :: proc(ctx: Context, accessor: ^cgltf.accessor, buffer: ^Buffer) {
	src_buffer_view := accessor.buffer_view
	src_buffer := src_buffer_view.buffer

	data_ptr := mem.ptr_offset(cast(^u8)src_buffer.data, accessor.offset + src_buffer_view.offset)
	copy_to_buffer(ctx, buffer, data_ptr)
}

@(private = "file")
get_accessor_type_size :: proc(type: cgltf.type) -> uint {
	switch type {
	case .invalid:
		log.panic("Invalid accessor type")
	case .scalar:
		return 4
	case .vec2:
		return 8
	case .vec3:
		return 12
	case .vec4:
		return 16
	case .mat2:
		return 2 * 8
	case .mat3:
		return 3 * 12
	case .mat4:
		return 3 * 16
	}

	// arghhhhh
	return 0
}

@(private = "file")
get_index_size_and_vk_type :: proc(type: cgltf.component_type) -> (uint, vk.IndexType) {
	#partial switch (type) {
	case .r_8u:
		return 1, .UINT8
	case .r_16u:
		return 2, .UINT16
	case .r_32u:
		return 4, .UINT32
	case:
		log.panicf("Invalid index type: %v", type)
	}
}

// there are no odin bindings for cgltf filters and wrap modes apparently
// also, these might not be set -> use linear filtering and clamp_to_edge

@(private = "file")
filter_cgltf_to_vk :: proc(cgltf_filter: i32) -> vk.Filter {
	switch (cgltf_filter) {
	case 9728, 9984, 9986:
		return .NEAREST
	case 9729, 9985, 9987:
		return .LINEAR
	}

	return .LINEAR
}

mipmap_mode_cgltf_to_vk :: proc(cgltf_filter: i32) -> vk.SamplerMipmapMode {
	switch (cgltf_filter) {
	case 9984, 9985:
		return .NEAREST
	case 9986, 9987:
		return .LINEAR
	}

	return .LINEAR
}

@(private = "file")
wrap_mode_cgltf_to_vk :: proc(cgltf_wrap_mode: i32) -> vk.SamplerAddressMode {
	switch (cgltf_wrap_mode) {
	case 33071:
		return .CLAMP_TO_EDGE
	case 33648:
		return .MIRRORED_REPEAT
	case 10497:
		return .REPEAT
	}

	return .CLAMP_TO_EDGE
}

