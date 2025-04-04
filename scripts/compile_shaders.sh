#!/bin/bash

glslc shaders/path_tracing.comp -o shaders/path_tracing.comp.spv
glslc shaders/post_process.vert -o shaders/post_process.vert.spv
glslc shaders/post_process.frag -o shaders/post_process.frag.spv
