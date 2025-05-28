package svk

import "core:log"

import vk "vendor:vulkan"

Draw_Context :: struct {
	max_frames_in_flight:          u32,
	current_frame:                 u32,
	image_index:                   u32,
	image_available_semaphores:    []vk.Semaphore,
	rendering_finished_semaphores: []vk.Semaphore,
	in_flight_fences:              []vk.Fence,
}

create_draw_context :: proc(
	ctx: Context,
	max_frames_in_flight: u32,
	loc := #caller_location,
) -> (
	draw_ctx: Draw_Context,
) {
	draw_ctx.max_frames_in_flight = max_frames_in_flight

	draw_ctx.image_available_semaphores = make([]vk.Semaphore, max_frames_in_flight, loc = loc)
	draw_ctx.rendering_finished_semaphores = make([]vk.Semaphore, max_frames_in_flight, loc = loc)
	draw_ctx.in_flight_fences = make([]vk.Fence, max_frames_in_flight, loc = loc)

	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	for i in 0 ..< max_frames_in_flight {
		result := vk.CreateSemaphore(
			ctx.device,
			&semaphore_info,
			nil,
			&draw_ctx.image_available_semaphores[i],
		)
		if result != .SUCCESS {
			log.panicf(
				"Failed to create the %d. image available semaphore (result: %v)",
				i,
				result,
			)
		}

		result = vk.CreateSemaphore(
			ctx.device,
			&semaphore_info,
			nil,
			&draw_ctx.rendering_finished_semaphores[i],
		)
		if result != .SUCCESS {
			log.panicf(
				"Failed to create the %d. rendering finished semaphore (result: %v)",
				i,
				result,
			)
		}

		result = vk.CreateFence(ctx.device, &fence_info, nil, &draw_ctx.in_flight_fences[i])
		if result != .SUCCESS {
			log.panicf("Failed to create the %d. in flight fence (result: %v)", i, result)
		}
	}

	return
}

destroy_draw_context :: proc(ctx: Context, draw_ctx: Draw_Context) {
	for i in 0 ..< draw_ctx.max_frames_in_flight {
		vk.DestroySemaphore(ctx.device, draw_ctx.image_available_semaphores[i], nil)
		vk.DestroySemaphore(ctx.device, draw_ctx.rendering_finished_semaphores[i], nil)
		vk.DestroyFence(ctx.device, draw_ctx.in_flight_fences[i], nil)
	}

	delete(draw_ctx.image_available_semaphores)
	delete(draw_ctx.rendering_finished_semaphores)
	delete(draw_ctx.in_flight_fences)
}

draw :: proc(ctx: ^Context, draw_ctx: ^Draw_Context, pipelines: ..^Pipeline) {
	current_frame := draw_ctx.current_frame

	image_available_semaphore := &draw_ctx.image_available_semaphores[current_frame]
	rendering_finished_semaphore := &draw_ctx.rendering_finished_semaphores[current_frame]
	in_flight_fence := draw_ctx.in_flight_fences[current_frame]

	image_index, out_of_date := aquire_next_image(ctx^, draw_ctx^, current_frame)
	if out_of_date {
		update_swapchain_capabilities(ctx)
		recreate_swapchain(ctx^, &ctx.swapchain)

		for &pipeline in pipelines {
			resize_pipeline(ctx^, pipeline)
		}

		return
	}

	command_buffer := ctx.command_buffers[current_frame]
	begin_command_buffer(command_buffer)

	transition_swapchain_image(ctx.swapchain.images[image_index], command_buffer)

	for pipeline in pipelines {
		configure_viewport(command_buffer, ctx.swapchain.extent)

		if pipeline.type == .graphics {
			log.assert(
				pipeline.render_pass != {},
				"A graphics pipeline needs to have a valid renderpass",
			)
			log.assert(
				len(pipeline.framebuffers) != 0,
				"A graphics pipeline needs to have framebuffers",
			)

			begin_render_pass(command_buffer, pipeline^, image_index, ctx.swapchain.extent)

			vk.CmdBindPipeline(command_buffer, .GRAPHICS, pipeline.handle)
		} else {
			vk.CmdBindPipeline(command_buffer, .COMPUTE, pipeline.handle)
		}

		log.assert(pipeline.record_fn != nil, "The pipeline record function must be set")
		pipeline.record_fn(ctx^, pipeline^, command_buffer, current_frame)

		if pipeline.type == .graphics {
			vk.CmdEndRenderPass(command_buffer)
		}
	}

	result := vk.EndCommandBuffer(command_buffer)
	if result != .SUCCESS {
		log.panicf("Failed to end the command buffer")
	}

	submit_command_buffer(
		ctx^,
		image_available_semaphore,
		rendering_finished_semaphore,
		in_flight_fence,
		&command_buffer,
	)

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = rendering_finished_semaphore,
		swapchainCount     = 1,
		pSwapchains        = &ctx.swapchain.handle,
		pImageIndices      = &image_index,
	}

	result = vk.QueuePresentKHR(ctx.graphics_queue.handle, &present_info)

	if result == .SUBOPTIMAL_KHR {
		update_swapchain_capabilities(ctx)
		recreate_swapchain(ctx^, &ctx.swapchain)

		for &pipeline in pipelines {
			resize_pipeline(ctx^, pipeline)
		}
	} else if result != .SUCCESS {
		log.panicf("Failed to present the command buffer (result: %v)", result)
	}

	draw_ctx.current_frame = (draw_ctx.current_frame + 1) % draw_ctx.max_frames_in_flight
}

wait_until_frame_is_done :: proc(ctx: Context, draw_ctx: Draw_Context) {
	frame := draw_ctx.current_frame
	in_flight_fence := &draw_ctx.in_flight_fences[frame]

	vk.WaitForFences(ctx.device, 1, in_flight_fence, false, ~cast(u64)0)
	vk.ResetFences(ctx.device, 1, in_flight_fence)
}

@(private = "file")
aquire_next_image :: proc(
	ctx: Context,
	draw_ctx: Draw_Context,
	current_frame: u32,
) -> (
	image_index: u32,
	out_of_date: bool,
) {
	result := vk.AcquireNextImageKHR(
		ctx.device,
		ctx.swapchain.handle,
		~u64(0),
		draw_ctx.image_available_semaphores[current_frame],
		vk.Fence{},
		&image_index,
	)

	if result == .ERROR_OUT_OF_DATE_KHR {
		return ~u32(0), true
	}

	if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
		log.panicf("Failed to aquire the next image (result: %v)", result)
	}

	return
}

@(private = "file")
begin_command_buffer :: proc(command_buffer: vk.CommandBuffer) {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	result := vk.BeginCommandBuffer(command_buffer, &begin_info)
	if result != .SUCCESS {
		log.panicf("Failed to begin the command buffer (result: %v)", result)
	}
}

@(private = "file")
transition_swapchain_image :: proc(image: vk.Image, command_buffer: vk.CommandBuffer) {
	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = {.MEMORY_WRITE},
		dstAccessMask = {},
		oldLayout = .UNDEFINED,
		newLayout = .PRESENT_SRC_KHR,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	vk.CmdPipelineBarrier(
		command_buffer,
		{.COMPUTE_SHADER},
		{.FRAGMENT_SHADER},
		vk.DependencyFlags{},
		0,
		nil,
		0,
		nil,
		1,
		&barrier,
	)
}

@(private = "file")
configure_viewport :: proc(command_buffer: vk.CommandBuffer, extent: vk.Extent2D) {
	viewport := vk.Viewport {
		x        = 0,
		width    = cast(f32)extent.width,
		y        = cast(f32)extent.height,
		height   = -cast(f32)extent.height,
		minDepth = 0,
		maxDepth = 1,
	}

	scissor := vk.Rect2D {
		extent = extent,
		offset = {0, 0},
	}

	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)
}

@(private = "file")
begin_render_pass :: proc(
	command_buffer: vk.CommandBuffer,
	pipeline: Pipeline,
	image_index: u32,
	extent: vk.Extent2D,
) {
	c := pipeline.clear_color
	clear_colors: [2]vk.ClearValue
	clear_colors[0].color.float32 = [4]f32{c.r, c.g, c.b, 1}
	clear_colors[1].depthStencil = {1, 0}

	render_pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = pipeline.render_pass,
		framebuffer = pipeline.framebuffers[image_index],
		renderArea = {extent = extent, offset = {0, 0}},
		clearValueCount = 2,
		pClearValues = raw_data(clear_colors[:]),
	}

	vk.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)
}

@(private = "file")
submit_command_buffer :: proc(
	ctx: Context,
	image_available_semaphore, rendering_finished_semaphore: ^vk.Semaphore,
	in_flight_fence: vk.Fence,
	command_buffer: ^vk.CommandBuffer,
) {
	@(static) stage_flag := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}

	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = image_available_semaphore,
		pWaitDstStageMask    = &stage_flag,
		commandBufferCount   = 1,
		pCommandBuffers      = command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = rendering_finished_semaphore,
	}

	result := vk.QueueSubmit(ctx.graphics_queue.handle, 1, &submit_info, in_flight_fence)
	if result != .SUCCESS {
		log.panicf("Failed to submit the command buffer (result: %v)", result)
	}
}

