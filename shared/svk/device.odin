package svk

import "core:log"

import vk "vendor:vulkan"

Device_Config :: struct {
	extensions: []cstring,
	features:   vk.PhysicalDeviceFeatures,
}

Swapchain_Support :: struct {
	capabilities:    vk.SurfaceCapabilitiesKHR,
	surface_formats: []vk.SurfaceFormatKHR,
	present_modes:   []vk.PresentModeKHR,
}

@(private)
create_devices_and_queues :: proc(
	ctx: ^Context,
	config: Device_Config,
	instance: vk.Instance,
	surface: vk.SurfaceKHR,
) {
	choose_physical_device_and_queues(ctx, config, instance, surface)
	choose_logical_device(ctx, config)

	vk.GetDeviceQueue(ctx.device, ctx.graphics_queue.family, 0, &ctx.graphics_queue.handle)
	vk.GetDeviceQueue(ctx.device, ctx.present_queue.family, 0, &ctx.present_queue.handle)
}

@(private = "file")
choose_physical_device_and_queues :: proc(
	ctx: ^Context,
	config: Device_Config,
	instance: vk.Instance,
	surface: vk.SurfaceKHR,
) {
	physical_device_count: u32
	vk.EnumeratePhysicalDevices(instance, &physical_device_count, nil)

	assert(physical_device_count != 0, "No physical devices were found")

	physical_devices := make([]vk.PhysicalDevice, physical_device_count)

	vk.EnumeratePhysicalDevices(instance, &physical_device_count, raw_data(physical_devices))

	for physical_device in physical_devices {
		graphics_queue, present_queue, found := get_queue_families(physical_device, surface)
		if !found {
			continue
		}

		swapchain_support, complete := query_swapchain_support(physical_device, surface)
		if !complete {
			continue
		}

		if !supports_extensions(physical_device, config.extensions) {
			continue
		}

		if !supports_features(physical_device, config.features) {
			continue
		}

		ctx.physical_device = physical_device
		ctx.graphics_queue.family = graphics_queue
		ctx.present_queue.family = present_queue
		ctx.swapchain_support = swapchain_support

		delete(physical_devices)
		return
	}

	log.panicf("Failed to find a physical device")
}

@(private = "file")
choose_logical_device :: proc(ctx: ^Context, config: Device_Config) {
	features := config.features

	// if the graphics_queue and present_queue are the same,
	// only the first element will be set
	// otherwise both are set
	queue_create_infos: [2]vk.DeviceQueueCreateInfo

	unique_queue_families := 1 if ctx.graphics_queue.family == ctx.present_queue.family else 2

	queue_family_indices := [2]u32{ctx.graphics_queue.family, ctx.present_queue.family}
	queue_priority: f32 = 1

	for i in 0 ..< unique_queue_families {
		queue_create_infos[i] = vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = queue_family_indices[i],
			queueCount       = 1,
			pQueuePriorities = &queue_priority,
		}
	}

	device_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = u32(unique_queue_families),
		pQueueCreateInfos       = raw_data(queue_create_infos[:]),
		enabledExtensionCount   = cast(u32)len(config.extensions),
		ppEnabledExtensionNames = raw_data(config.extensions[:]),
		pEnabledFeatures        = &features,
	}

	result := vk.CreateDevice(ctx.physical_device, &device_info, nil, &ctx.device)
	if result != .SUCCESS {
		log.panicf("Failed to create the logical device (result: %v)", result)
	}
}

@(private = "file")
get_queue_families :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (u32, u32, bool) {
	graphics_queue, present_queue: u32 = ~u32(0), ~u32(0)

	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)

	assert(queue_family_count != 0, "No queue families were found")

	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)

	vk.GetPhysicalDeviceQueueFamilyProperties(
		device,
		&queue_family_count,
		raw_data(queue_families),
	)

	for family, i in queue_families {
		if family.queueCount <= 0 {
			continue
		}

		if .GRAPHICS in family.queueFlags {
			graphics_queue = u32(i)
		}

		present_supported: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &present_supported)

		if present_supported {
			present_queue = u32(i)
		}

		if graphics_queue != ~u32(0) && present_queue != ~u32(0) {
			return graphics_queue, present_queue, true
		}
	}

	return 0, 0, false
}

@(private = "file")
query_swapchain_support :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> (
	Swapchain_Support,
	bool,
) {
	support: Swapchain_Support

	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &support.capabilities)
	surface_format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &surface_format_count, nil)

	if surface_format_count == 0 {
		return support, false
	}

	support.surface_formats = make([]vk.SurfaceFormatKHR, surface_format_count)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(
		device,
		surface,
		&surface_format_count,
		raw_data(support.surface_formats),
	)

	present_modes_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_modes_count, nil)

	if present_modes_count == 0 {
		return support, false
	}
	support.present_modes = make([]vk.PresentModeKHR, present_modes_count)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(
		device,
		surface,
		&present_modes_count,
		raw_data(support.present_modes),
	)

	return support, true
}

@(private = "file")
supports_extensions :: proc(device: vk.PhysicalDevice, required_extensions: []cstring) -> bool {
	extension_count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil)

	assert(extension_count != 0, "No device extension are available")

	available_extensions := make([]vk.ExtensionProperties, extension_count)
	defer delete(available_extensions)

	vk.EnumerateDeviceExtensionProperties(
		device,
		nil,
		&extension_count,
		raw_data(available_extensions),
	)

	found: int
	for &available in available_extensions {
		for required_name in required_extensions {
			available_name := cstring(&available.extensionName[0])

			if required_name == available_name {
				found += 1
				break
			}
		}
	}

	return found == len(required_extensions)
}

@(private = "file")
supports_features :: proc(
	device: vk.PhysicalDevice,
	required_features: vk.PhysicalDeviceFeatures,
) -> bool {
	required_features := required_features

	features: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceFeatures(device, &features)

	// there are exactly 55 features in the vk.PhysicalDeviceFeatures struct
	// all of them are b32's
	// yes this is scuffed

	features_ptr := cast([^]b32)&features.robustBufferAccess
	required_ptr := cast([^]b32)&required_features.robustBufferAccess

	for i in 0 ..< 55 {
		if features_ptr[i] == false && required_ptr[i] == true {
			return false
		}
	}

	return true
}

