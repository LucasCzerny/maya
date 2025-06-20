#version 450

layout(location = 0) rayPayloadInEXT hitPayload prd;

layout(buffer_reference, scalar) buffer Vertices { vec3 vertices[]; }
layout(set = 1, binding = idfk you stupid dumbass) buffer Object_Description { int i[]; } object_description;

void main() {
    Vertices vertices = Vertices()
}

