package main

import "core:math"
import "core:math/linalg"

import "vendor:glfw"

import "shared:svk"

Camera :: struct {
	position:  [3]f32,
	p0:        f32,
	direction: [3]f32,
	p1:        f32,
	right:     [3]f32,
	p2:        f32,
	up:        [3]f32,
}

create_camera :: proc(ctx: svk.Context) -> Camera {
	return Camera{[3]f32{0, 0, 1}, 0, [3]f32{0, 0, -1}, 0, [3]f32{1, 0, 0}, 0, [3]f32{0, 1, 0}}
}

update_camera :: proc(ctx: svk.Context, camera: ^Camera, delta_time: f64) -> (changed: bool) {
	movement_speed :: 5.0
	sensitivity :: 2.0

	glfw_window := ctx.window.handle

	@(static) prev_cursor_x, prev_cursor_y: f64 = 0, 0
	@(static) yaw, pitch := 3 * math.PI / 2, 0.0

	cursor_x, cursor_y := glfw.GetCursorPos(glfw_window)

	if glfw.GetMouseButton(glfw_window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS {
		glfw.SetInputMode(glfw_window, glfw.CURSOR, glfw.CURSOR_DISABLED)

		delta_x := cursor_x - prev_cursor_x
		delta_y := cursor_y - prev_cursor_y

		yaw -= delta_x * sensitivity * delta_time

		pitch -= delta_y * sensitivity * delta_time
		pitch = min(pitch, math.PI / 2)
		pitch = max(pitch, -math.PI / 2)

		camera.direction.x = cast(f32)(math.cos(yaw) * math.cos(pitch))
		camera.direction.y = cast(f32)math.sin(pitch)
		camera.direction.z = cast(f32)(math.sin(yaw) * math.cos(pitch))

		@(static) world_up := [3]f32{0, 1, 0}
		camera.right = linalg.normalize(linalg.cross(world_up, camera.direction))
		camera.up = linalg.normalize(linalg.cross(camera.direction, camera.right))

		changed = true
	} else {
		glfw.SetInputMode(glfw_window, glfw.CURSOR, glfw.CURSOR_NORMAL)
	}

	prev_cursor_x, prev_cursor_y = cursor_x, cursor_y

	forward, right, up: f32 = 0.0, 0.0, 0.0

	forward_changed := true
	if glfw.GetKey(glfw_window, glfw.KEY_W) == glfw.PRESS {
		forward = 1
	} else if glfw.GetKey(glfw_window, glfw.KEY_S) == glfw.PRESS {
		forward = -1
	} else {
		forward_changed = false
	}

	right_changed := true
	if glfw.GetKey(glfw_window, glfw.KEY_D) == glfw.PRESS {
		right = 1
	} else if glfw.GetKey(glfw_window, glfw.KEY_A) == glfw.PRESS {
		right = -1
	} else {
		right_changed = false
	}

	up_changed := true
	if glfw.GetKey(glfw_window, glfw.KEY_SPACE) == glfw.PRESS {
		up = 1
	} else if glfw.GetKey(glfw_window, glfw.KEY_LEFT_CONTROL) == glfw.PRESS {
		up = -1
	} else {
		up_changed = false
	}

	changed |= right_changed || up_changed || forward_changed

	camera.position +=
		(forward * camera.direction + right * camera.right + up * [3]f32{0, 1, 0}) *
		cast(f32)(movement_speed * delta_time)

	return
}

