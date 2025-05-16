package main

import "core:math/linalg"
import "core:slice"

import "shared:svk"

Bounded_Model :: struct {
	model:                   svk.Model,
	bounding_box_transforms: [dynamic]matrix[4, 4]f32,
}

create_bounded_model :: proc(ctx: svk.Context, model: svk.Model) -> (result: Bounded_Model) {
	result.model = model
	result.bounding_box_transforms = make([dynamic]matrix[4, 4]f32, 0, 1)

	for mesh in model.meshes {
		for primitive in mesh.primitives {
			transform := calculate_bounding_box(ctx, primitive)
			append(&result.bounding_box_transforms, transform)
		}
	}

	return
}

@(private = "file")
calculate_bounding_box :: proc(ctx: svk.Context, primitive: svk.Primitive) -> matrix[4, 4]f32 {
	positions_buffer := &primitive.vertex_buffers[.position]
	svk.map_buffer(ctx, positions_buffer)
	defer svk.unmap_buffer(ctx, positions_buffer)

	positions := slice.from_ptr(
		cast(^[3]f32)positions_buffer.mapped_memory,
		cast(int)positions_buffer.count,
	)

	x_bounds := [2]f32{max(f32), min(f32)}
	y_bounds := [2]f32{max(f32), min(f32)}
	z_bounds := [2]f32{max(f32), min(f32)}

	for position in positions {
		x := position.x
		y := position.y
		z := position.z

		if x < x_bounds[0] {
			x_bounds[0] = x
		}
		if x > x_bounds[1] {
			x_bounds[1] = x
		}

		if y < y_bounds[0] {
			y_bounds[0] = y
		}
		if y > y_bounds[1] {
			y_bounds[1] = y
		}

		if z < z_bounds[0] {
			z_bounds[0] = z
		}
		if z > z_bounds[1] {
			z_bounds[1] = z
		}
	}

	size_x := x_bounds[1] - x_bounds[0]
	size_y := y_bounds[1] - y_bounds[0]
	size_z := z_bounds[1] - z_bounds[0]

	center_x := x_bounds[0] + size_x / 2
	center_y := y_bounds[0] + size_y / 2
	center_z := z_bounds[0] + size_z / 2

	transform := linalg.matrix4_translate(
		[3]f32{center_x / size_x, center_y / size_y, center_z / size_z},
	)
	transform *= linalg.matrix4_scale([3]f32{size_x, size_y, size_z})

	return transform
}

