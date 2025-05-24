#version 450

layout(location = 0) in vec3 position;

layout(push_constant) Transforms {
    mat4 model_transform;  
    mat4 bounding_box_transform;
};

layout(location = 0, binding = 0) uniform Camera {
    mat4 view_projection_matrix;
};

void main() {
    gl_Position = view_projection_matrix * model_transform * bounding_box_transform * position;
}
