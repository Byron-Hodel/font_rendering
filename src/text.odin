package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:math/linalg/glsl"
import "vendor:stb/truetype"
import gl "vendor:OpenGL"

MAX_FONT_TEXTURES :: 1024
MAX_FONT_QUADS :: 2048

Rect :: distinct [4]f32

Character_Data :: struct {
    glyph_index: i32,
    depth_index: u32,
}

Font :: struct {
    info:                truetype.fontinfo,
    empy_char:           Character_Data,
    char_data:           map[rune]Character_Data,
    vert_buffer:         u32,
    ubo:                 u32,
    tex_width:           i32,
    tex_height:          i32,
    tex_buffer:          []u8,
    tex_array_depth:     u32,
    tex_array_max_depth: u32,
    tex_array:           u32,
    instance_count:      u32,
    ubo_data:            [MAX_FONT_QUADS]Text_Quad,
}

Vert :: distinct glsl.vec2

Text_Quad :: struct #align(8) {
    offset:    glsl.vec2,
    scale:     glsl.vec2,
    col:       glsl.vec3,
    tex_index: i32,
}

font_init :: proc(font: ^Font, font_file: os.Handle) {
    content, ok := os.read_entire_file(font_file)
    assert(ok, "failed to read file; also, no error handling here")
    
    truetype.InitFont(&font.info, raw_data(content), 0)

    font.tex_width = 64
    font.tex_height = 64
    font.tex_buffer = make([]u8, font.tex_width * font.tex_height)

    verts: [4]Vert
    verts[0] = {0,0}  // bottom left
    verts[1] = {0,1}  // top left
    verts[2] = {1,0}  // bottom right
    verts[3] = {1,1}  // top right

    buffers: [2]u32
    gl.GenBuffers(2, raw_data(&buffers))
    font.vert_buffer = buffers[0]
    font.ubo = buffers[1]

    gl.BindBuffer(gl.ARRAY_BUFFER, font.vert_buffer)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(Vert) * 4, raw_data(&verts), gl.STATIC_DRAW)
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)

    gl.BindBuffer(gl.UNIFORM_BUFFER, font.ubo)
    gl.BufferData(gl.UNIFORM_BUFFER, size_of(font.ubo_data), nil, gl.DYNAMIC_DRAW)
    gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

    font.tex_array_depth = 0
    font.tex_array_max_depth = 512
    gl.GenTextures(1, &font.tex_array)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D_ARRAY, font.tex_array)
    gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER)
    gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER)
    gl.TexImage3D(gl.TEXTURE_2D_ARRAY, 0, gl.RED, font.tex_width, font.tex_height,
                  cast(i32)font.tex_array_max_depth, 0, gl.RED, gl.UNSIGNED_BYTE, nil)
}

font_deinit :: proc(font: ^Font) {
    gl.DeleteBuffers(1, &font.vert_buffer)
    gl.DeleteTextures(1, &font.tex_array)
    delete(font.tex_buffer)
}

font_rasterize_codepoint :: proc(font: ^Font, codepoint: rune) -> (Character_Data, bool) {
    if font.tex_array_depth >= font.tex_array_max_depth {
        fmt.eprintln("No more space in texture array")
        return font.empy_char, {}
    }
    index: i32 = truetype.FindGlyphIndex(&font.info, codepoint)
    if index == 0 {
        return font.empy_char, false
    }
    width := font.tex_width
    height := font.tex_height
    write_ptr: [^]u8 = raw_data(font.tex_buffer[:])

    scale_x, scale_y: f32
    {
        x0, x1, y0, y1: i32
        truetype.GetGlyphBox(&font.info, index, &x0, &y0, &x1, &y1)
        scale_x = (cast(f32)width) / cast(f32)(x1-x0)
        scale_y = (cast(f32)height) / cast(f32)(y1-y0)
    }
    
    truetype.MakeGlyphBitmap(&font.info, write_ptr, width, height, font.tex_width, scale_x, scale_y, index)

    depth: u32 = font.tex_array_depth
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D_ARRAY, font.tex_array)
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    gl.TexSubImage3D(gl.TEXTURE_2D_ARRAY, 0, 0, 0, cast(i32)depth, font.tex_width, font.tex_height,
                     1, gl.RED, gl.UNSIGNED_BYTE, raw_data(font.tex_buffer))
    font.tex_array_depth += 1

    //tex := create_bmp_tex(width, height, raw_data(font.tex_buffer))
    //font.tex_handles[font.tex_handle_count] = tex
    //defer font.tex_handle_count += 1
    
    c_data := Character_Data {
        glyph_index = index,
        depth_index = depth,
    }
    font.char_data[codepoint] = c_data
    return c_data, true
}

// start_pos: the start position of text measured in pixels
draw_text :: proc(font: ^Font, start_pos: glsl.vec2, str: string, height: f32, shader: u32) #no_bounds_check {
    pos: glsl.vec2 = start_pos
    line_height: i32 = cast(i32)height

    ascent, decent, line_gap: i32
    truetype.GetFontVMetrics(&font.info, &ascent, &decent, &line_gap)
    scale: f32 = height / cast(f32)(ascent - decent)

    gl.UseProgram(shader)
    gl.BindBuffer(gl.ARRAY_BUFFER, font.vert_buffer)
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0)

    gl.BindBuffer(gl.UNIFORM_BUFFER, font.ubo)
    gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, font.ubo)
    defer gl.BindBuffer(gl.UNIFORM_BUFFER, 0)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Vert), 0)

    //ubo_index := gl.GetUniformBlockIndex(shader, "Quad")
    //gl.UniformBlockBinding(shader, ubo_index, 0)

    prev_char_data: Character_Data
    for codepoint, index in str {
        if codepoint == '\n' {
            pos = {start_pos.x, pos.y - cast(f32)(line_height+line_gap)}
            continue
        }

        char_data, has_codepoint := font.char_data[codepoint]
        defer prev_char_data = char_data
        if !has_codepoint {
            data, found_codepoint := font_rasterize_codepoint(font, codepoint)
            if !found_codepoint {
                
            }
        }

        advance_width, left_bearing: i32
        truetype.GetGlyphHMetrics(&font.info, char_data.glyph_index, &advance_width, &left_bearing)

        if codepoint == ' ' {
            pos += {cast(f32)advance_width * scale, 0}
            continue
        }

        kern: i32 = 0
        if index > 0 {
            kern = truetype.GetGlyphKernAdvance(&font.info, prev_char_data.glyph_index, char_data.glyph_index)
        }
        x0, y0, x1, y1: i32
        truetype.GetGlyphBitmapBox(&font.info, char_data.glyph_index, scale, scale, &x0, &y0, &x1, &y1)
        bottom: f32 = cast(f32)-y1
        left: f32 = cast(f32)(left_bearing+kern) * scale

        truetype.GetGlyphBox(&font.info, char_data.glyph_index, &x0, &y0, &x1, &y1)
        width: f32 = cast(f32)(x1 - x0) * scale
        height: f32 = cast(f32)(y1 - y0) * scale

        ubo_index := font.instance_count
        font.ubo_data[ubo_index].offset = pos + {left, bottom}
        font.ubo_data[ubo_index].scale = {width, height}
        font.ubo_data[ubo_index].col = {1,1,1}
        font.ubo_data[ubo_index].tex_index = cast(i32)char_data.depth_index
        font.instance_count += 1

        if ubo_index >= MAX_FONT_QUADS {
            gl.ActiveTexture(gl.TEXTURE0)
            gl.BindTexture(gl.TEXTURE_2D_ARRAY, font.tex_array)
            gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(font.ubo_data), &font.ubo_data)
            gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, cast(i32)font.instance_count)
            font.instance_count = 0
        }

        //gl.ActiveTexture(gl.TEXTURE0)
        //gl.BindTexture(gl.TEXTURE_2D, font.tex_handles[char_data.tex_index])
        //gl.DrawArrays(gl.TRIANGLE_STRIP, 0, len(verts))
        pos += {cast(f32)advance_width * scale, 0}
    }
    gl.BufferSubData(gl.UNIFORM_BUFFER, 0, cast(int)(size_of(Text_Quad) * font.instance_count), &font.ubo_data)
    gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, cast(i32)font.instance_count)
    font.instance_count = 0
}

create_bmp_tex :: proc(width, height: i32, data: [^]u8) -> u32 {
    tex: u32
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    gl.GenTextures(1, &tex)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, tex)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT, width, height, 0, gl.DEPTH_COMPONENT, gl.UNSIGNED_BYTE, data)
    return tex
}

