#version 430 core

layout(location=0) in vec4 col;
layout(location=1) in vec2 coord;
layout(location=2) in flat int depth_index;

layout(binding=0) uniform sampler2DArray tex_array;

out vec4 color;

void main() {
    vec4 sample_color = vec4(1,1,1, texture(tex_array, vec3(coord,depth_index)).r);
    color = sample_color * col;
}
