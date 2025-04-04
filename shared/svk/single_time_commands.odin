package svk

import "core:log"

import vk "vendor:vulkan"

begin_single_time_commands :: proc(ctx: Context) -> (command_buffer: vk.CommandBuffer) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}

	result := vk.AllocateCommandBuffers(ctx.device, &alloc_info, &command_buffer)
	if result != .SUCCESS {
		log.panicf("Failed to allocate the single time command buffer (result: %v)", result)
	}

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	result = vk.BeginCommandBuffer(command_buffer, &begin_info)
	if result != .SUCCESS {
		log.panicf("Failed to begin the single time command buffer (result: %v)", result)
	}

	return
}

end_single_time_commands :: proc(ctx: Context, command_buffer: ^vk.CommandBuffer) {
	result := vk.EndCommandBuffer(command_buffer^)
	if result != .SUCCESS {
		log.panicf("Failed to end the single time command buffer (result: %v)", result)
	}

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = command_buffer,
	}

	vk.QueueSubmit(ctx.graphics_queue.handle, 1, &submit_info, vk.Fence{})
	vk.QueueWaitIdle(ctx.graphics_queue.handle)

	vk.FreeCommandBuffers(ctx.device, ctx.command_pool, 1, command_buffer)
}

