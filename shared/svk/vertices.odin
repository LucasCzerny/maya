package svk

import "core:log"

import vk "vendor:vulkan"

Pos_2D :: struct {
	position: [2]f32,
}

Pos_Tex_2D :: struct {
	position:   [2]f32,
	tex_coords: [2]f32,
}

// interleaved
binding_descriptions_pos_2d :: proc(
	loc := #caller_location,
) -> (
	descriptions: []vk.VertexInputBindingDescription,
) {
	descriptions = make([]vk.VertexInputBindingDescription, 1, loc = loc)

	descriptions[0] = {
		binding   = 0,
		stride    = size_of([2]f32),
		inputRate = .VERTEX,
	}

	return
}

// interleaved
attribute_descriptions_pos_2d :: proc(
	loc := #caller_location,
) -> (
	descriptions: []vk.VertexInputAttributeDescription,
) {
	descriptions = make([]vk.VertexInputAttributeDescription, 1, loc = loc)

	descriptions[0] = {
		binding  = 0,
		location = 0,
		format   = .R32G32_SFLOAT,
		offset   = 0,
	}

	return
}

// interleaved
binding_descriptions_pos_tex_2d :: proc(
	loc := #caller_location,
) -> (
	descriptions: []vk.VertexInputBindingDescription,
) {
	descriptions = make([]vk.VertexInputBindingDescription, 1, loc = loc)

	descriptions[0] = {
		binding   = 0,
		stride    = size_of([2]f32) + size_of([2]f32),
		inputRate = .VERTEX,
	}

	return
}

// interleaved
attribute_descriptions_pos_tex_2d :: proc(
	loc := #caller_location,
) -> (
	descriptions: []vk.VertexInputAttributeDescription,
) {
	descriptions = make([]vk.VertexInputAttributeDescription, 2, loc = loc)

	descriptions[0] = {
		binding  = 0,
		location = 0,
		format   = .R32G32_SFLOAT,
		offset   = 0,
	}

	descriptions[1] = {
		binding  = 0,
		location = 1,
		format   = .R32G32_SFLOAT,
		offset   = size_of([2]f32),
	}

	return
}

// non-interleaved
binding_descriptions_from_attributes :: proc(
	attributes: []Model_Attribute,
	loc := #caller_location,
) -> (
	descriptions: []vk.VertexInputBindingDescription,
) {
	count := len(attributes)
	descriptions = make([]vk.VertexInputBindingDescription, count, loc = loc)

	for attribute, i in attributes {
		descriptions[i] = {
			binding   = cast(u32)i,
			stride    = cast(u32)get_stride_for_attribute(attribute),
			inputRate = .VERTEX,
		}
	}

	return
}

// non-interleaved
attribute_descriptions_from_attributes :: proc(
	attributes: []Model_Attribute,
	loc := #caller_location,
) -> (
	descriptions: []vk.VertexInputAttributeDescription,
) {
	count := len(attributes)
	descriptions = make([]vk.VertexInputAttributeDescription, count, loc = loc)

	for attribute, i in attributes {
		descriptions[i] = {
			binding  = cast(u32)i,
			location = cast(u32)i,
			format   = vertex_format_from_attribute(attribute),
			offset   = 0,
		}
	}

	return
}

destroy_vertex_descriptions :: proc(
	binding_descriptions: []vk.VertexInputBindingDescription,
	attribute_descriptions: []vk.VertexInputAttributeDescription,
) {
	delete(binding_descriptions)
	delete(attribute_descriptions)
}

@(private = "file")
get_stride_for_attribute :: proc(attribute: Model_Attribute) -> uint {
	switch (attribute) {
	case .invalid:
		log.panic("Why are you using the invalid attribute it's called invalid for a reason")
	case .position:
		return size_of([3]f32)
	case .normal:
		return size_of([3]f32)
	case .tangent:
		return size_of([4]f32)
	case .tex_coord:
		return size_of([2]f32)
	case .color:
		return size_of([3]f32)
	case .joints:
		return size_of([4]f32)
	case .weights:
		return size_of([4]f32)
	case .custom:
		return size_of([4]f32)
	}

	// compiler mad if unreachable return statement is not there
	return 0
}

@(private = "file")
vertex_format_from_attribute :: proc(attribute: Model_Attribute) -> vk.Format {
	switch (attribute) {
	case .invalid:
		log.panic("Why are you using the invalid attribute it's called invalid for a reason")
	case .position:
		return .R32G32B32_SFLOAT
	case .normal:
		return .R32G32B32_SFLOAT
	case .tangent:
		return .R32G32B32A32_SFLOAT
	case .tex_coord:
		return .R32G32_SFLOAT
	case .color:
		return .R32G32B32_SFLOAT
	case .joints:
		return .R32G32B32A32_SFLOAT
	case .weights:
		return .R32G32B32A32_SFLOAT
	case .custom:
		return .R32G32B32A32_SFLOAT
	}

	// compiler mad if unreachable return statement is not there
	return {}
}

