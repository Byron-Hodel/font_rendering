package main
import "core:fmt"
import "core:os"
import "core:math/linalg/glsl"
import "core:time"
import "vendor:glfw"
import gl "vendor:OpenGL"
import "core:strings"
import "core:math"

VERT_SRC :: #load("../text.vert", string)
FRAG_SRC :: #load("../text.frag", string)
TEXT :: #load("../text.txt", string)

input_str_builder: strings.Builder

main :: proc() {
    input_state: Input_State
    window: glfw.WindowHandle
    font: Font

    if !glfw.Init() {
        fmt.eprintln("failed to init glfw")
        return
    }
    defer glfw.Terminate()
    fmt.println("initialized glfw")

    window = glfw.CreateWindow(500, 500, "text rendering", nil, nil)
    defer glfw.DestroyWindow(window)
    fmt.println("created window")
    glfw.SetKeyCallback(window, cast(glfw.KeyProc)key_callback)

    glfw.MakeContextCurrent(window)
    gl.load_up_to(3, 3, glfw.gl_set_proc_address)
    fmt.println("loaded opengl version 3.3")
    glfw.SwapInterval(0)

    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    gl.Enable(gl.BLEND)

    FONT_PATH :: "Open_Sans/OpenSans-VariableFont_wdth,wght.ttf"
    file, errno := os.open(FONT_PATH)
    if errno != os.F_OK {
        fmt.eprintln("failed to open font file:", FONT_PATH)
        return
    }
    font_init(&font, file)
    defer font_deinit(&font)
    os.close(file)

    shader_handle, shader_ok := gl.load_shaders_source(VERT_SRC, FRAG_SRC)
    if !shader_ok {
        msg, shader_type := gl.get_last_error_message()
        fmt.eprintln("failed to load shader:", shader_type, msg)
        return
    }
    view_loc := gl.GetUniformLocation(shader_handle, "view")
    if view_loc == -1 {
        fmt.eprintln("failed to get view uniform location")
    }
    
    input_str_builder = strings.builder_make()
    defer strings.builder_destroy(&input_str_builder)

    // frame time is a rolling average of the last n frames
    AVG_COUNT :: 256
    frame_times: [AVG_COUNT]f32
    frame_time_sum: f32 = 0
    frame_time_count: u32 = 0
    frame_time_buffer: [32]byte
    frame_time_str: string
    sw: time.Stopwatch

    prev_width, prev_height: i32
    //draw_text(&font, {100, 100}, "t", shader_handle)
    for !glfw.WindowShouldClose(window) {
        time.stopwatch_reset(&sw)
        time.stopwatch_start(&sw)
        defer { // calculate frame time rolling average
            duration := time.stopwatch_duration(sw)
            miliseconds := time.duration_milliseconds(duration)
            index: u32
            if frame_time_count == AVG_COUNT {
                index = AVG_COUNT-1
                frame_time_sum -= frame_times[0]
                for i in 0..<AVG_COUNT-1 {
                    frame_times[i] = frame_times[i+1]
                }
            }
            else {
                index = frame_time_count
                frame_time_count += 1
            }
            frame_time_sum += cast(f32)miliseconds
            frame_times[index] = cast(f32)miliseconds
            avg_ms: f32 = (frame_time_sum / cast(f32)frame_time_count)
            avg_fps: u32 = cast(u32)math.round(1000 / avg_ms)
            frame_time_str = fmt.bprintf(frame_time_buffer[:], "frame time: %.1fms (%dfps)", avg_ms, avg_fps)
        }

        glfw.PollEvents()
        //defer input_state = input_state_update(input_state)

        mouse_pos: glsl.vec2
        window_width, window_height := glfw.GetWindowSize(window)
        if prev_width != window_width || prev_height != window_height {
            prev_width = window_width
            prev_height = window_height 
            gl.Viewport(0, 0, window_width, window_height)

            view: glsl.mat4 = glsl.mat4Ortho3d(0, cast(f32)window_width, 0, cast(f32)window_height, 0, 10)
            gl.UseProgram(shader_handle)
            gl.UniformMatrix4fv(view_loc, 1, gl.FALSE, raw_data(&view))
        }
        {
            x_pos, y_pos := glfw.GetCursorPos(window)
            mouse_pos = {cast(f32)x_pos, cast(f32)window_height-cast(f32)y_pos}
        }

        // pauses rendering
        if pause {
            continue;
        }

        gl.ClearColor(0.1, 0.1, 0.1, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        defer glfw.SwapBuffers(window)
        
        //draw_text(&font, {500, 100}, strings.to_string(input_str_builder), line_height, shader_handle)
        //draw_text(&font, mouse_pos, "abcdefghijklmnopqrstuvwxyz", line_height, shader_handle)
        draw_text(&font, mouse_pos, TEXT, line_height, shader_handle)
        draw_text(&font, {20, 20}, frame_time_str, line_height, shader_handle)
    }
}

line_height: f32 = 32
pause: b8 = false

key_callback :: proc(window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    switch key {
    case glfw.KEY_ESCAPE:
        if action == 1 {
            pause = !pause
        }
        return
    case glfw.KEY_RIGHT_BRACKET:
        if action == 1 {
            break
        }
        line_height = min(512, line_height+4)
        return
    case glfw.KEY_LEFT_BRACKET:
        if action == 1 {
            break
        }
        line_height = max(4, line_height-4)
        return
    case glfw.KEY_BACKSPACE:
        if action != 0 && len(input_str_builder.buf) > 0 {
            pop(&input_str_builder.buf)
        }
        return
    }
    if action != 0 {
        //strings.write_rune(&input_str_builder, cast(rune)key)
    }
}
