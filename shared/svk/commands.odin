package svk

import "core:log"

import vk "vendor:vulkan"

Commands_Config :: struct {
	nr_command_buffers: u32,
}

@(private)
create_command_pool :: proc(ctx: ^Context, config: Commands_Config) {
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.TRANSIENT, .RESET_COMMAND_BUFFER},
		queueFamilyIndex = ctx.graphics_queue.family,
	}

	result := vk.CreateCommandPool(ctx.device, &pool_info, nil, &ctx.command_pool)
	if result != .SUCCESS {
		log.panicf("Failed to create the command pool (result: %v)", result)
	}
}

@(private)
create_command_buffers :: proc(ctx: ^Context, config: Commands_Config) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.command_pool,
		level              = .PRIMARY,
		commandBufferCount = config.nr_command_buffers,
	}

	ctx.command_buffers = make([]vk.CommandBuffer, config.nr_command_buffers)

	result := vk.AllocateCommandBuffers(ctx.device, &alloc_info, raw_data(ctx.command_buffers))
	if result != .SUCCESS {
		log.panicf("Failed to create the command buffers (result: %v)", result)
	}
}

