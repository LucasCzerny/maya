#version 450

layout(location = 0) in vec2 position;
layout(location = 1) in vec2 tex_coords;

layout(location = 0) out vec2 tex_coords_out;

void main() {
    tex_coords_out = tex_coords;
    
    gl_Position = vec4(position, 0.0, 1.0);
}
