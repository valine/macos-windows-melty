"""Fractional Cocoa resizes at a screen wall, without global mouse input.

Run with a MeltyGUI Python, axis x/y and an output JSON path. Requires the
installed Melty Windows utility; use isolated XDG/session directories.
"""
import json
import sys
import time
from pathlib import Path

import meltygui
from meltygui import imgui, window_api as glfw
from meltygui.core.core_render import render_func
from meltygui.core.layout import column_core
from meltygui.core.melty import Melty
from meltygui.core.runtime.toggles import Toggles
from meltygui.core.windowing import os_frame, melty_windows
from meltygui.core.windowing.surface import Surface

axis, output = sys.argv[1:]
index = 0 if axis == 'x' else 1
output = Path(output)
Toggles.Melty.push_os_window_edges = True
Toggles.Melty.wayland_show_frame = True
os_frame._any_button_down = lambda: True
state = dict(start=time.monotonic(), placed=False, settle=0, index=0)
steps = [25.25] * 15 + [0.] * 3 + [-25.25] * 15 + [0.] * 3
samples = []


def advance(window, ds):
    try:
        if os_frame.mode() != 'cocoa':
            assert time.monotonic() - state['start'] < 5, 'Cocoa agreement missing'
        elif not state['placed']:
            x, y, w, h = melty_windows.workarea(window)
            wall = (x + w, y + h)[index]
            position = list(glfw.get_window_pos(window))
            position[index] = int(wall - glfw.get_window_size(window)[index])
            glfw.set_window_pos(window, *position)
            state.update(placed=True, wall=wall, settle=3)
        elif state['settle']:
            state['settle'] -= 1
        else:
            position, size = glfw.get_window_pos(window), glfw.get_window_size(window)
            sample = dict(frame=Melty.frame_count, position=position, size=size,
                          far=position[index] + size[index], wall=state['wall'])
            samples.append(sample)
            assert sample['far'] == state['wall'], sample
            if state['index'] == len(steps):
                output.write_text(json.dumps(dict(passed=True, samples=samples)))
                glfw.set_window_should_close(window, True)
                return
            far = column_core._frame(ds, axis)[1]
            increment = steps[state['index']]
            column_core._pending(ds, axis).append((far, far[axis] + increment, True))
            state['index'] += 1
        Surface.active.request_frame()
    except Exception as error:
        output.write_text(json.dumps(dict(passed=False, error=repr(error), samples=samples)))
        glfw.set_window_should_close(window, True)


@meltygui.glfw_window(name='Native boundary resize check', app_id='native-boundary-probe', width=800, height=800)
@render_func(use_cache=False, show_header=False, determines_height=False)
def check(input_value: object = None, draw_state=None, column_edges=None, row_edges=None):
    if axis == 'x':
        layout = column_core.ColumnLayout(draw_state, 2, column_edges=column_edges,
                                          column_widths=[None, 40.], column_mins=[60., 40.])
    else:
        layout = column_core.RowLayout(draw_state, 2, row_edges=row_edges,
                                       row_heights=[None, 40.], row_mins=[60., 40.])
    for cell in range(2):
        with layout.cell(cell):
            imgui.text('The outer edge must remain exactly on the screen boundary.')
    layout.finish()
    Melty.post_to_render(lambda: advance(Surface.active.window, draw_state))
    return False, input_value


meltygui.run()
