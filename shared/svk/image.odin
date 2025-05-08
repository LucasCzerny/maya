package svk

import "core:bytes"
import "core:image"
import "core:image/png" // just for registering the loader and destroyer
import "core:log"
_ :: png // don't complain about the unused import >.<

import vk "vendor:vulkan"

Image :: struct {
	handle:        vk.Image,
	view:          vk.ImageView,
	memory:        vk.DeviceMemory,
	width, height: u32,
	depth:         u32,
	channels:      u32,
	format:        vk.Format,
	layout:        vk.ImageLayout,
}

load_image :: proc {
	load_image_from_file,
	load_image_from_bytes,
}

load_image_from_file :: proc(
	ctx: Context,
	path: string,
	srgb: bool,
	tiling: vk.ImageTiling = .OPTIMAL,
	usage: vk.ImageUsageFlags = {.SAMPLED},
	layout: vk.ImageLayout = .SHADER_READ_ONLY_OPTIMAL,
) -> Image {
	img_data, err := image.load_from_file(path, {.alpha_add_if_missing})
	if err != nil {
		log.panicf("Failed to load the image from the specified path (err: %v)", err)
	}

	defer image.destroy(img_data)

	img := create_image(
		ctx,
		cast(u32)img_data.width,
		cast(u32)img_data.height,
		cast(u32)img_data.depth,
		cast(u32)img_data.channels,
		srgb,
		tiling,
		usage + {.TRANSFER_DST},
		layout,
	)

	copy_to_image(ctx, img, raw_data(bytes.buffer_to_bytes(&img_data.pixels)))

	return img
}

load_image_from_bytes :: proc(
	ctx: Context,
	data_bytes: []u8,
	srgb: bool,
	tiling: vk.ImageTiling = .OPTIMAL,
	usage: vk.ImageUsageFlags = {.SAMPLED},
	layout: vk.ImageLayout = .SHADER_READ_ONLY_OPTIMAL,
) -> Image {
	img_data, err := image.load_from_bytes(data_bytes, {.alpha_add_if_missing})
	if err != nil {
		log.panicf("Failed to load the image from the specified path (err: %v)", err)
	}

	defer image.destroy(img_data)

	img := create_image(
		ctx,
		cast(u32)img_data.width,
		cast(u32)img_data.height,
		cast(u32)img_data.depth,
		cast(u32)img_data.channels,
		srgb,
		tiling,
		usage + {.TRANSFER_DST},
		layout,
	)

	copy_to_image(ctx, img, raw_data(bytes.buffer_to_bytes(&img_data.pixels)))

	return img
}

create_image :: proc(
	ctx: Context,
	width, height: u32,
	depth: u32,
	channels: u32,
	srgb: bool,
	tiling: vk.ImageTiling = .OPTIMAL,
	usage: vk.ImageUsageFlags = {.SAMPLED},
	layout: vk.ImageLayout = .SHADER_READ_ONLY_OPTIMAL,
) -> (
	img: Image,
) {
	img.format = determine_format(channels, depth, srgb)

	queue_families := [2]u32{ctx.graphics_queue.family, ctx.present_queue.family}

	image_info := vk.ImageCreateInfo {
		sType                 = .IMAGE_CREATE_INFO,
		imageType             = .D2,
		format                = img.format,
		extent                = {width, height, 1},
		mipLevels             = 1,
		arrayLayers           = 1,
		samples               = {._1},
		tiling                = tiling,
		usage                 = usage,
		sharingMode           = .EXCLUSIVE,
		queueFamilyIndexCount = len(queue_families),
		pQueueFamilyIndices   = raw_data(queue_families[:]),
		initialLayout         = .UNDEFINED,
	}

	result := vk.CreateImage(ctx.device, &image_info, nil, &img.handle)
	if result != .SUCCESS {
		log.panicf("Failed to create the image (result: %v)", result)
	}

	mem_requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(ctx.device, img.handle, &mem_requirements)

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = find_memory_type_index(ctx, mem_requirements, {.DEVICE_LOCAL}),
	}

	result = vk.AllocateMemory(ctx.device, &alloc_info, nil, &img.memory)
	if result != .SUCCESS {
		log.panicf("Failed to create the image memory (result: %v)", result)
	}

	result = vk.BindImageMemory(ctx.device, img.handle, img.memory, 0)
	if result != .SUCCESS {
		log.panicf("Failed to bind the image memory (result: %v)", result)
	}

	view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = img.handle,
		viewType = .D2,
		format = img.format,
		components = {.R, .G, .B, .A},
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			layerCount = 1,
			baseMipLevel = 0,
			levelCount = 1,
		},
	}

	result = vk.CreateImageView(ctx.device, &view_info, nil, &img.view)
	if result != .SUCCESS {
		log.panicf("Failed to create the image view (result: %v)", result)
	}

	img.width = width
	img.height = height
	img.depth = depth
	img.channels = channels

	img.layout = layout

	return
}

copy_to_image :: proc(ctx: Context, img: Image, pixels: rawptr, loc := #caller_location) {
	log.infof("Make sure you added .TRANSFER_DST to the image usage (at: %v)", loc)

	staging_buffer := create_buffer(
		ctx,
		1,
		img.width * img.height * img.channels,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)

	copy_to_buffer(ctx, &staging_buffer, pixels)

	transition_image(
		ctx,
		img,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.TOP_OF_PIPE},
		{.TRANSFER},
		{},
		{.TRANSFER_WRITE},
	)

	copy_from_staging_buffer(ctx, img, staging_buffer)

	transition_image(
		ctx,
		img,
		.TRANSFER_DST_OPTIMAL,
		img.layout,
		{.TRANSFER},
		{.FRAGMENT_SHADER},
		{.TRANSFER_READ},
		{.SHADER_READ},
	)

	destroy_buffer(ctx, staging_buffer)
}

destroy_image :: proc(ctx: Context, img: Image) {
	vk.DestroyImage(ctx.device, img.handle, nil)
	vk.DestroyImageView(ctx.device, img.view, nil)
	vk.FreeMemory(ctx.device, img.memory, nil)
}

transition_image :: proc(
	ctx: Context,
	image: Image,
	from, to: vk.ImageLayout,
	src_stage_mask, dst_stage_mask: vk.PipelineStageFlags,
	src_access_mask, dst_access_mask: vk.AccessFlags,
	command_buffer: vk.CommandBuffer = vk.CommandBuffer{},
) {
	command_buffer := command_buffer
	use_single_time_commands := command_buffer == {}

	if use_single_time_commands {
		command_buffer = begin_single_time_commands(ctx)
	}

	memory_barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = from,
		newLayout = to,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		srcAccessMask = src_access_mask,
		dstAccessMask = dst_access_mask,
		image = image.handle,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			layerCount = 1,
			baseMipLevel = 0,
			levelCount = 1,
		},
	}

	vk.CmdPipelineBarrier(
		command_buffer,
		src_stage_mask,
		dst_stage_mask,
		{},
		0,
		nil,
		0,
		nil,
		1,
		&memory_barrier,
	)

	if use_single_time_commands {
		end_single_time_commands(ctx, &command_buffer)
	}
}

// TODO: ugh
@(private = "file")
determine_format :: proc(channels, depth: u32, srgb: bool) -> vk.Format {
	log.assert(
		channels == 4,
		"Most GPUs only really support images with 4 channels (so does (for now?))",
	)

	log.assert(depth == 8, "Tbh don't feel like implementing this shit rn")

	format_int := cast(i32)vk.Format.R8G8B8A8_UNORM
	if srgb do format_int += 6

	return cast(vk.Format)format_int
}

@(private = "file")
copy_from_staging_buffer :: proc(ctx: Context, image: Image, buffer: Buffer) {
	command_buffer := begin_single_time_commands(ctx)

	region := vk.BufferImageCopy {
		imageSubresource = vk.ImageSubresourceLayers {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		imageExtent = {image.width, image.height, 1},
	}

	vk.CmdCopyBufferToImage(
		command_buffer,
		buffer.handle,
		image.handle,
		.TRANSFER_DST_OPTIMAL,
		1,
		&region,
	)

	end_single_time_commands(ctx, &command_buffer)
}

