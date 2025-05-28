package main

import "core:log"
import "core:mem"

import "vendor:glfw"

import "shared:svk"

MAX_FRAMES_IN_FLIGHT :: 2

main :: proc() {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger(
			opt = {.Level, .Short_File_Path, .Line, .Procedure, .Terminal_Color},
		)
		defer log.destroy_console_logger(context.logger)
	}

	when ODIN_DEBUG {
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		defer {
			for _, entry in tracking_allocator.allocation_map {
				context.logger = {}
				log.warnf("%v leaked %d bytes", entry.location, entry.size)
			}

			for entry in tracking_allocator.bad_free_array {
				context.logger = {}
				log.warnf("%v bad free on %v", entry.location, entry.memory)
			}

			mem.tracking_allocator_destroy(&tracking_allocator)
		}
	}

	ctx := create_context()
	// defer svk.destroy_context(ctx)

	draw_ctx := svk.create_draw_context(ctx, MAX_FRAMES_IN_FLIGHT)
	// defer svk.destroy_draw_context(ctx, draw_ctx)

	last_time := glfw.GetTime()

	for !glfw.WindowShouldClose(ctx.window.handle) {
		svk.wait_until_frame_is_done(ctx, draw_ctx)

		time := glfw.GetTime()
		delta_time := time - last_time
		last_time = time

		log.info(delta_time)

		// svk.draw(&ctx, &draw_ctx, &path_tracing_pipeline)

		glfw.SwapBuffers(ctx.window.handle)
		glfw.PollEvents()
	}

	panic("Fix those errors bro")
}

create_context :: proc() -> svk.Context {
	instance_config :: svk.Instance_Config {
		name                     = "maya",
		major                    = 0,
		minor                    = 1,
		patch                    = 0,
		extensions               = {"VK_EXT_debug_utils"},
		enable_validation_layers = true,
	}

	window_config :: svk.Window_Config {
		window_title   = "maya",
		initial_width  = 1280,
		initial_height = 720,
		resizable      = true,
		fullscreen     = false,
	}

	device_config :: svk.Device_Config {
		extensions = {
			"VK_KHR_swapchain",
			"VK_KHR_acceleration_structure",
			"VK_KHR_ray_tracing_pipeline",
			"VK_KHR_deferred_host_operations",
			"VK_KHR_buffer_device_address",
			"VK_EXT_descriptor_indexing",
		},
		features = {samplerAnisotropy = true},
	}

	swapchain_config :: svk.Swapchain_Config {
		format       = .B8G8R8A8_SRGB,
		color_space  = .COLORSPACE_SRGB_NONLINEAR,
		present_mode = .MAILBOX,
	}

	commands_config :: svk.Commands_Config {
		nr_command_buffers = MAX_FRAMES_IN_FLIGHT,
	}

	descriptor_config :: svk.Descriptor_Config {
		max_sets                  = 6,
		nr_storage_image          = 1,
		nr_combined_image_sampler = 1,
		nr_storage_buffer         = 4,
	}

	return svk.create_context(
		instance_config,
		window_config,
		device_config,
		swapchain_config,
		commands_config,
		descriptor_config,
	)
}

