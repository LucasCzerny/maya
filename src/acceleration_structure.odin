package main

import "shared:svk"

import vk "vendor:vulkan"

Acceleration_Structure :: struct {
	handle: vk.AccelerationStructureKHR,
	buffer: svk.Buffer,
}

destroy_acceleration_structure :: proc(ctx: svk.Context, blas: Acceleration_Structure) {
	vk.DestroyAccelerationStructureKHR(ctx.device, blas.handle, nil)
	svk.destroy_buffer(ctx, blas.buffer)
}
