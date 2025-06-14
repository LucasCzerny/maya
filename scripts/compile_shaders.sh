#!/bin/bash

glslc --target-env=vulkan1.3 shaders/basic.rgen -o shaders/basic.rgen.spv
glslc --target-env=vulkan1.3 shaders/basic.miss -o shaders/basic.miss.spv
glslc --target-env=vulkan1.3 shaders/basic.rchit -o shaders/basic.rchit.spv
