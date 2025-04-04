package main

import "core:math"
import "core:math/linalg"

import "vendor:glfw"

import "shared:svk"

Camera :: struct {
	position:      [3]f32,
	sphere_angles: [2]f32,
	radius:        f32,
}

@(private = "file")
scroll_delta: f32 = 0

create_camera :: proc(ctx: svk.Context, radius: f32) -> Camera {
	glfw.SetScrollCallback(ctx.window.handle, scroll_callback)
	return Camera{{radius, 0, 0}, {0, 0}, radius}
}

update_camera :: proc(ctx: svk.Context, camera: ^Camera, delta_time: f32) -> bool {
	sensitivity :: 0.01
	scroll_speed :: 1

	update_position := false

	if scroll_delta != 0 {
		camera.radius -= scroll_delta * scroll_speed
		camera.radius = math.clamp(camera.radius, 0, 10)

		update_position = true
		scroll_delta = 0
	}

	@(static) previous_cursor := [2]f32{0, 0}

	cursor_x, cursor_y := glfw.GetCursorPos(ctx.window.handle)
	cursor_pos := [2]f32{cast(f32)cursor_x, cast(f32)cursor_y}

	change := cursor_pos - previous_cursor
	previous_cursor = cursor_pos

	if glfw.GetMouseButton(ctx.window.handle, glfw.MOUSE_BUTTON_LEFT) != glfw.PRESS {
		glfw.SetInputMode(ctx.window.handle, glfw.CURSOR, glfw.CURSOR_NORMAL)
		if !update_position do return false
	}

	glfw.SetInputMode(ctx.window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)

	if !update_position && change == {0, 0} {
		return false
	}

	camera.sphere_angles += change * sensitivity
	camera.sphere_angles.y = math.clamp(camera.sphere_angles.y, -math.PI / 2, math.PI / 2)
	
	// odinfmt: disable
	camera.position = linalg.normalize([3]f32{
		linalg.cos(camera.sphere_angles.x),
		linalg.sin(camera.sphere_angles.y),
		linalg.sin(camera.sphere_angles.x),
	}) * camera.radius
	// odinfmt: enable

	return true
}

calculate_view_projection_matrix :: proc(ctx: svk.Context, camera: Camera) -> matrix[4, 4]f32 {
	aspect_ratio := cast(f32)ctx.window.width / cast(f32)ctx.window.height
	fov_y := linalg.to_radians(cast(f32)60)

	projection_matrix := linalg.matrix4_perspective(fov_y, aspect_ratio, 0.01, 100)

	from := camera.position
	to :: [3]f32{0, 0, 0}
	up_dir :: [3]f32{0, 1, 0}

	view_matrix := linalg.matrix4_look_at(from, to, up_dir)

	return projection_matrix * view_matrix
}

@(private = "file")
scroll_callback :: proc "c" (window: glfw.WindowHandle, x_offset, y_offset: f64) {
	scroll_delta = cast(f32)y_offset
}

