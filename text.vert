#version 430 core

layout(location=0) in vec2 pos;

layout(location=0) out vec4 col;
layout(location=1) out vec2 coord;
layout(location=2) out flat int depth_index;

layout(location=0) uniform mat4 view;

#define MAX_QUADS 2048

struct Quad {
    vec2 offset;
    vec2 scale;
    vec3 col;
    int depth_index;
};

layout(std140, binding=0) uniform Quad_UBO {
    Quad quads[MAX_QUADS];
};

void main() {
    coord = vec2(pos.x, 1 - pos.y);

    int index = gl_InstanceID;
    vec2 offset = quads[index].offset;
    vec2 scale = quads[index].scale;
    depth_index = quads[index].depth_index;
    col = vec4(quads[index].col.xyz,1);
    
    vec2 position = pos * scale + offset;
    gl_Position = view * vec4(position.xy, 0, 1);
}
