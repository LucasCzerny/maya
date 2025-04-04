#version 450

layout(location = 0) in vec2 tex_coords;

layout(location = 0) out vec4 color;

layout(set = 0, binding = 0) uniform sampler2D frame;

void main() {
    color = texture(frame, tex_coords);
}
