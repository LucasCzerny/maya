package svk

import "core:log"

import vk "vendor:vulkan"

@(private)
create_debug_messenger :: proc(
	messenger: ^vk.DebugUtilsMessengerEXT,
	instance: vk.Instance,
	context_copy: rawptr,
) {
	create_func := cast(vk.ProcCreateDebugUtilsMessengerEXT)vk.GetInstanceProcAddr(
		instance,
		"vkCreateDebugUtilsMessengerEXT",
	)
	if create_func == nil {
		log.panic("The CreateDebugUtilsMessengerEXT function was not found")
	}

	messenger_info := vk.DebugUtilsMessengerCreateInfoEXT {
		sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR},
		messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING},
		pfnUserCallback = vulkan_debug_callback,
		pUserData       = context_copy,
	}

	result := create_func(instance, &messenger_info, nil, messenger)
	if result != .SUCCESS {
		log.panic("Failed to create the debug messenger (result: %v)", result)
	}
}

@(private)
destroy_debug_messenger :: proc(messenger: vk.DebugUtilsMessengerEXT, instance: vk.Instance) {
	destroy_func := cast(vk.ProcDestroyDebugUtilsMessengerEXT)vk.GetInstanceProcAddr(
		instance,
		"vkDestroyDebugUtilsMessengerEXT",
	)
	if destroy_func == nil {
		log.panic("The CreateDebugUtilsMessengerEXT function was not found")
	}

	destroy_func(instance, messenger, nil)
}

