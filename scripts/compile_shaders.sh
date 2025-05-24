#!/bin/bash

glslc --target-env=vulkan1.3 shaders/path_tracing.comp -o shaders/path_tracing.comp.spv
glslc --target-env=vulkan1.3 shaders/post_process.vert -o shaders/post_process.vert.spv
glslc --target-env=vulkan1.3 shaders/post_process.frag -o shaders/post_process.frag.spv
