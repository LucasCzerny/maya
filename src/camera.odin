package main

import "core:math"
import "core:math/linalg"

import "vendor:glfw"

import "shared:svk"

Camera :: struct {
	projection:     matrix[4, 4]f32,
	view:           matrix[4, 4]f32,
	projection_inv: matrix[4, 4]f32,
	view_inv:       matrix[4, 4]f32,
}

create_camera :: proc(ctx: svk.Context, width, height: u32) -> Camera {
	proj := linalg.matrix4_perspective_f32(45, cast(f32)width / cast(f32)height, 0.1, 1000)
	view := calculate_view_matrix([3]f32{0, 0, 1}, [3]f32{0, 0, -1})

	return Camera {
		projection = proj,
		view = view,
		projection_inv = linalg.inverse(proj),
		view_inv = linalg.matrix4x4_inverse(view),
	}
}

update_camera :: proc(ctx: svk.Context, camera: ^Camera, delta_time: f64) -> (changed: bool) {
	movement_speed :: 5.0
	sensitivity :: 2.0

	@(static) position := [3]f32{0, 0, 1}
	@(static) yaw, pitch := 3 * math.PI / 2, 0.0

	glfw_window := ctx.window.handle
	cursor_x, cursor_y := glfw.GetCursorPos(glfw_window)
	@(static) prev_cursor_x, prev_cursor_y: f64 = 0, 0

	if glfw.GetMouseButton(glfw_window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS {
		glfw.SetInputMode(glfw_window, glfw.CURSOR, glfw.CURSOR_DISABLED)

		delta_x := cursor_x - prev_cursor_x
		delta_y := cursor_y - prev_cursor_y

		yaw += delta_x * sensitivity * delta_time
		pitch -= delta_y * sensitivity * delta_time
		pitch = math.clamp(pitch, -math.PI / 2, math.PI / 2)

		changed = true
	} else {
		glfw.SetInputMode(glfw_window, glfw.CURSOR, glfw.CURSOR_NORMAL)
	}

	move := [3]f32{0, 0, 0}
	if glfw.GetKey(glfw_window, glfw.KEY_W) == glfw.PRESS {move.z += 1}
	if glfw.GetKey(glfw_window, glfw.KEY_S) == glfw.PRESS {move.z -= 1}
	if glfw.GetKey(glfw_window, glfw.KEY_D) == glfw.PRESS {move.x += 1}
	if glfw.GetKey(glfw_window, glfw.KEY_A) == glfw.PRESS {move.x -= 1}
	if glfw.GetKey(glfw_window, glfw.KEY_SPACE) == glfw.PRESS {move.y += 1}
	if glfw.GetKey(glfw_window, glfw.KEY_LEFT_CONTROL) == glfw.PRESS {move.y -= 1}

	if move != 0 {
		forward := [3]f32 {
			cast(f32)(math.cos(yaw) * math.cos(pitch)),
			cast(f32)math.sin(pitch),
			cast(f32)(math.sin(yaw) * math.cos(pitch)),
		}
		right := linalg.normalize(linalg.cross(forward, [3]f32{0, 1, 0}))
		up := [3]f32{0, 1, 0}

		movement := move.x * right + move.y * up + move.z * forward
		position += movement * cast(f32)(movement_speed * delta_time)
		changed = true
	}

	if changed {
		direction := [3]f32 {
			cast(f32)(math.cos(yaw) * math.cos(pitch)),
			cast(f32)math.sin(pitch),
			cast(f32)(math.sin(yaw) * math.cos(pitch)),
		}
		camera.view = linalg.matrix4_look_at(position, position + direction, [3]f32{0, 1, 0})
		camera.view_inv = linalg.inverse(camera.view)
	}

	prev_cursor_x, prev_cursor_y = cursor_x, cursor_y
	return
}

@(private = "file")
calculate_view_matrix :: proc(position: [3]f32, direction: [3]f32) -> matrix[4, 4]f32 {
	forward := linalg.normalize(direction)

	world_up := [3]f32{0, 1, 0}
	right := linalg.normalize(linalg.cross(forward, world_up))
	up := linalg.normalize(linalg.cross(right, forward))

	return matrix[4, 4]f32{
		right.x, right.y, right.z, -linalg.dot(right, position), 
		up.x, up.y, up.z, -linalg.dot(up, position), 
		-forward.x, -forward.y, -forward.z, linalg.dot(forward, position), 
		0, 0, 0, 1, 
	}
}

