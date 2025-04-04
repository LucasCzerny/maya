package svk

import vk "vendor:vulkan"

Queue :: struct {
	handle: vk.Queue,
	family: u32,
}

