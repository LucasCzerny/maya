#!/bin/bash

glslc --target-env=vulkan1.3 shaders/path_tracing.vert -o shaders/path_tracing.vert.spv
glslc --target-env=vulkan1.3 shaders/path_tracing.frag -o shaders/path_tracing.frag.spv
