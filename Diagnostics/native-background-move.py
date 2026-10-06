"""Interactive MeltyGUI native-move acceptance fixture; isolate XDG state paths.

Use normal desktop input to drag the patterned background, then the orange
control. The first must move only the native origin; the second must change
the value without moving the window. The JSONL records input/geometry evidence.
"""
import json
import sys
import time
from pathlib import Path

import meltygui
from AppKit import NSApplication, NSEvent
from meltygui import imgui, window_api as glfw
from meltygui.core.core_render import render_func
from meltygui.core.melty import Melty
from meltygui.core.windowing import melty_windows as bridge
from meltygui.core.windowing.surface import Surface

output = Path(sys.argv[1])


def record(kind, **values):
    with output.open('a') as stream:
        stream.write(json.dumps(dict(kind=kind, at=time.monotonic(), **values)) + '\n')


begin = bridge.begin_move


def begin_move(window):
    accepted = begin(window)
    record('handoff', accepted=accepted)
    return accepted


bridge.begin_move = begin_move
capture = bridge.capture_move_press


def capture_move_press(window, button, action):
    event = NSApplication.sharedApplication().currentEvent()
    record('button', button=button, action=action, native_type=event.type() if event else None,
           physical=NSEvent.pressedMouseButtons())
    capture(window, button, action)


bridge.capture_move_press = capture_move_press
original_frame = Surface.frame
previous = None


def frame(surface):
    global previous
    original_frame(surface)
    state = dict(position=glfw.get_window_pos(surface.window), size=glfw.get_window_size(surface.window),
                 left=glfw.get_mouse_button(surface.window, glfw.MOUSE_BUTTON_LEFT),
                 ready=bridge.move_available(surface.window))
    if state != previous:
        record('frame', **state)
        previous = state
    if state['left']:
        record('routing', events={str(k): list(v) for k, v in Melty.events.items()},
               capture=repr(Melty.event_handler._drag_capture))


Surface.frame = frame


value = 0.


@meltygui.glfw_window(name='Melty native move check', app_id='melty-native-move-check')
@render_func(use_cache=False, show_header=False, determines_height=False)
def check(input_value: object = None, draw_state=None):
    global value
    draw = imgui.get_window_draw_list()
    x, y = imgui.get_cursor_screen_pos()
    for offset in range(0, 700, 24):
        draw.add_line(x + offset, y + 140, x + offset + 120, y + 380, 0xff735b42, 2.)
    imgui.text('Drag the striped empty area to move this native window.')
    imgui.text('The orange control must keep its own left drag.')
    rect = (x + 20, y + 60, x + 440, y + 120)
    draw.add_rect_filled(*rect, 0xff224077)
    draw.add_text(x + 30, y + 80, 0xffffffff, f'Drag this control: {value:.0f}')
    drag = draw_state.on_action('left_mouse_drag', view_id='orange-control', rect=rect)
    if drag is not None:
        value += drag.dx
        record('control', value=value)
    return False, input_value


meltygui.run()
