package svk

import "core:log"
import "core:math"

import vk "vendor:vulkan"

Swapchain_Config :: struct {
	format:       vk.Format,
	color_space:  vk.ColorSpaceKHR,
	present_mode: vk.PresentModeKHR,
	// set to 0 to use ctx.swapchain_support.capabilities.minImageCount + 1
	// should be a good default
	image_count:  u32,
}

Swapchain :: struct {
	handle:               vk.SwapchainKHR,
	//
	surface_format:       vk.SurfaceFormatKHR,
	depth_format:         vk.Format,
	present_mode:         vk.PresentModeKHR,
	extent:               vk.Extent2D,
	//
	image_count:          u32,
	images:               []vk.Image,
	image_views:          []vk.ImageView,
	depth_images:         []vk.Image,
	depth_image_views:    []vk.ImageView,
	depth_image_memories: []vk.DeviceMemory,
	// don't modify
	_config:              Swapchain_Config,
	_old_swapchain:       vk.SwapchainKHR,
}

create_swapchain :: proc(ctx: Context, config: Swapchain_Config) -> (swapchain: Swapchain) {
	swapchain._config = config
	recreate_swapchain(ctx, &swapchain)
	return
}

recreate_swapchain :: proc(ctx: Context, swapchain: ^Swapchain) {
	vk.DeviceWaitIdle(ctx.device)

	// destroy old stuff before creating new stuff
	if len(swapchain.images) != 0 {
		for i in 0 ..< swapchain.image_count {
			vk.DestroyImageView(ctx.device, swapchain.image_views[i], nil)

			vk.DestroyImage(ctx.device, swapchain.depth_images[i], nil)
			vk.DestroyImageView(ctx.device, swapchain.depth_image_views[i], nil)
			vk.FreeMemory(ctx.device, swapchain.depth_image_memories[i], nil)
		}
	}

	delete(swapchain.images)
	delete(swapchain.image_views)

	delete(swapchain.depth_images)
	delete(swapchain.depth_image_views)
	delete(swapchain.depth_image_memories)

	swapchain._old_swapchain = swapchain.handle

	swapchain.surface_format, swapchain.depth_format = choose_surface_formats(
		swapchain._config,
		ctx.swapchain_support.surface_formats,
		ctx.physical_device,
	)
	swapchain.present_mode = choose_present_mode(
		swapchain._config,
		ctx.swapchain_support.present_modes,
	)
	swapchain.extent = choose_extent(ctx.window, ctx.swapchain_support.capabilities)

	if swapchain._config.image_count != 0 {
		swapchain.image_count = swapchain._config.image_count
	} else {
		swapchain.image_count = ctx.swapchain_support.capabilities.minImageCount + 1
	}

	max_image_count := ctx.swapchain_support.capabilities.maxImageCount
	if max_image_count > 0 && swapchain.image_count > max_image_count {
		swapchain.image_count = max_image_count
	}

	swapchain_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = ctx.window.surface,
		minImageCount    = swapchain.image_count,
		imageFormat      = swapchain.surface_format.format,
		imageColorSpace  = swapchain.surface_format.colorSpace,
		imageExtent      = swapchain.extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = {.IDENTITY},
		compositeAlpha   = {.OPAQUE},
		presentMode      = swapchain.present_mode,
		clipped          = true,
		oldSwapchain     = swapchain._old_swapchain,
	}

	queue_family_indices := [2]u32{ctx.graphics_queue.family, ctx.present_queue.family}

	if queue_family_indices[0] == queue_family_indices[1] {
		swapchain_info.imageSharingMode = .EXCLUSIVE
		swapchain_info.queueFamilyIndexCount = 0
		swapchain_info.pQueueFamilyIndices = nil
	} else {
		swapchain_info.imageSharingMode = .CONCURRENT
		swapchain_info.queueFamilyIndexCount = 2
		swapchain_info.pQueueFamilyIndices = raw_data(queue_family_indices[:])
	}

	result := vk.CreateSwapchainKHR(ctx.device, &swapchain_info, nil, &swapchain.handle)
	if result != .SUCCESS {
		log.panicf("Failed to create the swapchain (result: %v)", result)
	}

	if swapchain._old_swapchain != {} {
		vk.DestroySwapchainKHR(ctx.device, swapchain._old_swapchain, nil)
	}

	create_images(swapchain, ctx.device)
	create_depth_resources(ctx, swapchain)
}

destroy_swapchain :: proc(ctx: Context, swapchain: Swapchain) {
	vk.DeviceWaitIdle(ctx.device)

	vk.DestroySwapchainKHR(ctx.device, swapchain.handle, nil)

	for i in 0 ..< swapchain.image_count {
		vk.DestroyImageView(ctx.device, swapchain.image_views[i], nil)

		vk.DestroyImage(ctx.device, swapchain.depth_images[i], nil)
		vk.DestroyImageView(ctx.device, swapchain.depth_image_views[i], nil)
		vk.FreeMemory(ctx.device, swapchain.depth_image_memories[i], nil)
	}

	delete(swapchain.images)
	delete(swapchain.image_views)

	delete(swapchain.depth_images)
	delete(swapchain.depth_image_views)
	delete(swapchain.depth_image_memories)
}

@(private = "file")
choose_surface_formats :: proc(
	config: Swapchain_Config,
	formats: []vk.SurfaceFormatKHR,
	physical_device: vk.PhysicalDevice,
) -> (
	image_format: vk.SurfaceFormatKHR,
	depth_format: vk.Format,
) {
	found := false
	for format in formats {
		if format.format == config.format && format.colorSpace == config.color_space {
			image_format = format
			found = true
			break
		}
	}

	if !found {
		image_format = formats[0]

		log.warn(
			"The requested swapchain format and color space combination is not available, defaulting to the first format in the array (format: %v, color space: %v)",
			image_format.format,
			image_format.colorSpace,
		)
	}

	found = false
	depth_formats :: [3]vk.Format{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}

	for format in depth_formats {
		format_properties: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physical_device, format, &format_properties)

		if .DEPTH_STENCIL_ATTACHMENT in format_properties.optimalTilingFeatures {
			depth_format = format
			found = true
			break
		}
	}

	if !found {
		panic(
			"None of the formats .D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT are supported",
		)
	}

	return
}

@(private = "file")
choose_present_mode :: proc(
	config: Swapchain_Config,
	modes: []vk.PresentModeKHR,
) -> vk.PresentModeKHR {
	for mode in modes {
		if mode == config.present_mode {
			return mode
		}
	}

	log.warn("The requested swapchain present mode is not available, defaulting to .FIFO")

	return .FIFO
}

@(private = "file")
choose_extent :: proc(window: Window, capabilities: vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
	extent := vk.Extent2D{window.width, window.height}

	extent.width = math.clamp(
		extent.width,
		capabilities.minImageExtent.width,
		capabilities.maxImageExtent.width,
	)

	extent.height = math.clamp(
		extent.height,
		capabilities.minImageExtent.height,
		capabilities.maxImageExtent.height,
	)

	return extent
}

@(private = "file")
create_images :: proc(swapchain: ^Swapchain, device: vk.Device) {
	vk.GetSwapchainImagesKHR(device, swapchain.handle, &swapchain.image_count, nil)
	assert(swapchain.image_count != 0, "The swapchain image count is 0")

	swapchain.images = make([]vk.Image, swapchain.image_count)

	result := vk.GetSwapchainImagesKHR(
		device,
		swapchain.handle,
		&swapchain.image_count,
		raw_data(swapchain.images),
	)
	if result != .SUCCESS {
		log.panicf("Failed to get the swapchain images (result: %v)", result)
	}

	view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = .D2,
		format = swapchain.surface_format.format,
		components = vk.ComponentMapping{.R, .G, .B, .A},
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			layerCount = 1,
			baseMipLevel = 0,
			levelCount = 1,
		},
	}

	swapchain.image_views = make([]vk.ImageView, swapchain.image_count)

	for image, i in swapchain.images {
		view_info.image = image

		result = vk.CreateImageView(device, &view_info, nil, &swapchain.image_views[i])
		if result != .SUCCESS {
			log.panicf("Failed to create an image view (result: %v)", result)
		}
	}
}

@(private = "file")
create_depth_resources :: proc(ctx: Context, swapchain: ^Swapchain) {
	image_info := vk.ImageCreateInfo {
		sType                 = .IMAGE_CREATE_INFO,
		imageType             = .D2,
		format                = swapchain.depth_format,
		extent                = {swapchain.extent.width, swapchain.extent.height, 1},
		mipLevels             = 1,
		arrayLayers           = 1,
		samples               = {._1},
		tiling                = .OPTIMAL,
		pQueueFamilyIndices   = raw_data(
			[]u32{ctx.graphics_queue.family, ctx.present_queue.family},
		),
		usage                 = {.DEPTH_STENCIL_ATTACHMENT},
		sharingMode           = .EXCLUSIVE,
		queueFamilyIndexCount = ctx.graphics_queue == ctx.present_queue ? 1 : 2,
		initialLayout         = .UNDEFINED,
	}

	view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = .D2,
		format = swapchain.depth_format,
		components = vk.ComponentMapping{.R, .G, .B, .A},
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = {.DEPTH},
			baseArrayLayer = 0,
			layerCount = 1,
			baseMipLevel = 0,
			levelCount = 1,
		},
	}

	swapchain.depth_images = make([]vk.Image, swapchain.image_count)
	swapchain.depth_image_views = make([]vk.ImageView, swapchain.image_count)
	swapchain.depth_image_memories = make([]vk.DeviceMemory, swapchain.image_count)

	for i in 0 ..< swapchain.image_count {
		result := vk.CreateImage(ctx.device, &image_info, nil, &swapchain.depth_images[i])
		if result != .SUCCESS {
			log.panicf("Failed to create a swapchain depth image (result: %v)", result)
		}

		image := swapchain.depth_images[i]

		mem_requirements: vk.MemoryRequirements
		vk.GetImageMemoryRequirements(ctx.device, image, &mem_requirements)

		alloc_info := vk.MemoryAllocateInfo {
			sType           = .MEMORY_ALLOCATE_INFO,
			allocationSize  = mem_requirements.size,
			memoryTypeIndex = find_memory_type_index(ctx, mem_requirements, {.DEVICE_LOCAL}),
		}

		result = vk.AllocateMemory(
			ctx.device,
			&alloc_info,
			nil,
			&swapchain.depth_image_memories[i],
		)
		if result != .SUCCESS {
			log.panicf("Failed to create a swapchain depth memory (result: %v)")
		}

		memory := swapchain.depth_image_memories[i]

		result = vk.BindImageMemory(ctx.device, image, memory, 0)
		if result != .SUCCESS {
			log.panicf("Failed to bind a swapchain depth memory (result: %v)")
		}

		view_info.image = swapchain.depth_images[i]

		result = vk.CreateImageView(ctx.device, &view_info, nil, &swapchain.depth_image_views[i])
		if result != .SUCCESS {
			log.panicf("Failed to create a swapchain depth image view (result: %v)", result)
		}
	}
}

