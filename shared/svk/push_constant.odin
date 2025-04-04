package svk

import vk "vendor:vulkan"

Push_Constant_Config :: struct {
	offset:      u32,
	size:        u32,
	stage_flags: vk.ShaderStageFlags,
	data:        rawptr,
}

Push_Constant :: struct {
	handle: vk.PushConstantRange,
	data:   rawptr,
}

create_push_constant :: proc(
	ctx: Context,
	config: Push_Constant_Config,
) -> (
	push_constant: Push_Constant,
) {
	push_constant.handle = {
		offset     = config.offset,
		size       = config.size,
		stageFlags = config.stage_flags,
	}

	push_constant.data = config.data

	return
}

