package svk

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:strings"

import vk "vendor:vulkan"

@(private = "file")
Message :: struct {
	function_name: string,
	description:   string,
	spec_states:   string,
}

@(private)
vulkan_debug_callback: vk.ProcDebugUtilsMessengerCallbackEXT : proc "c" (
	message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	message_types: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	if .VERBOSE in message_severity || .INFO in message_severity {
		return false
	}

	context = (cast(^runtime.Context)user_data)^

	builder := strings.builder_make()
	strings.write_string(&builder, "\n")

	msg, err := split_message(callback_data.pMessage)
	if err {
		log.warn("Failed to format the error message")
		log.error(callback_data.pMessage)
		return true
	}

	red_ansi := "\033[31m"
	gray_ansi := "\033[2m"
	clear_ansi := "\033[0m"

	strings.write_string(
		&builder,
		fmt.aprintfln("%swhere:%s %s", red_ansi, clear_ansi, msg.function_name),
	)
	strings.write_string(
		&builder,
		fmt.aprintfln("%swhat:%s %s", red_ansi, clear_ansi, msg.description),
	)
	strings.write_string(
		&builder,
		fmt.aprintf(
			"%svulkan spec:%s %s%s%s",
			red_ansi,
			clear_ansi,
			gray_ansi,
			msg.spec_states,
			clear_ansi,
		),
	)

	log.error(strings.to_string(builder))

	strings.builder_destroy(&builder)

	return true
}

split_message :: proc(message: cstring) -> (result: Message, err: bool) {
	msg := string(message)
	parts := strings.split(msg, " | ")
	if len(parts) < 2 do return {}, true

	function_name_rest := strings.split_n(parts[2], ":", 2)
	if len(function_name_rest) < 2 do return {}, true

	result.function_name = function_name_rest[0]
	rest := function_name_rest[1]

	description_spec_states := strings.split(rest, "\nThe Vulkan spec states: ")
	if len(description_spec_states) < 2 do return {}, true

	result.description = description_spec_states[0]
	result.spec_states = description_spec_states[1]

	return
}
