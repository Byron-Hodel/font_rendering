package main

Mouse_Button :: enum {
    LEFT,
    RIGHT,
    MIDDLE,
}

Key_State :: enum {
    NONE,     // key not interacted with
    PRESSED,  // was the key pressed this frame
    HELD,     // is the key held down for more than 1 frame
    RELEASED, // was the key released this frame
}

Key :: enum {
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    ZERO,
    ONE,
    TWO,
    THREE,
    FOUR,
    FIVE,
    SIX,
    SEVEN,
    EIGHT,
}

Input_State :: struct {
    mouse: [Mouse_Button]b8,
    keys:  [Key]Key_State,
}

input_state_update :: proc(state: Input_State) -> Input_State {
    using Key_State
    new_state: Input_State
    new_state.mouse = state.mouse
    for key_state, i in state.keys {
        #partial switch key_state {
        case PRESSED:
            new_state.keys[i] = HELD
        case RELEASED:
            new_state.keys[i] = NONE
        }
    }
    return state
}
