"""Real decorated MeltyGUI surface: native push, stationary hold, and reversal.

Run with a MeltyGUI Python environment, axis x/y and a result JSON path.
Requires the installed Melty Windows service. Uses no synthetic global input.
"""
import json
import sys
import time
from pathlib import Path

import meltygui
from meltygui import imgui, window_api as glfw
from meltygui.core.core_render import render_func
from meltygui.core.layout.column_core import ColumnLayout, RowLayout
from meltygui.core.melty import Melty
from meltygui.core.runtime.toggles import Toggles
from meltygui.core.windowing import os_frame, titlebar
from meltygui.core.windowing.surface import Surface

axis, result_path = sys.argv[1:]
result_path = Path(result_path)
Toggles.Melty.push_os_window_edges = True
Toggles.Melty.wayland_show_frame = True
os_frame._any_button_down = lambda: True
state = dict(start=time.monotonic(), stage=0, settle=0, travel=0.)
frames = []


def advance(window, draw_state, edges):
    try:
        if os_frame.mode() != 'cocoa':
            assert time.monotonic() - state['start'] < 5, 'service did not enable Cocoa edges'
            Surface.active.request_frame()
            return
        box = (*glfw.get_window_pos(window), *glfw.get_window_size(window))
        frames.append(dict(box=box, divider=edges[1][axis], travel=state['travel']))
        assert not Surface.active.chrome
        assert edges[1][axis] - edges[0][axis] >= 119
        assert edges[2][axis] - edges[1][axis] >= 199
        if state['settle']:
            state['settle'] -= 1
            Surface.active.request_frame()
            return
        stage = state['stage']
        if stage == 0:
            state['initial'] = box
            travel = -500.
        elif stage == 1:
            assert box != state['initial'], ('native edge did not move', frames)
            state['pushed'] = box
            travel = -500.
        elif stage == 2:
            assert box == state['pushed'], ('stationary gesture accumulated movement', frames)
            travel = 0.
        else:
            assert all(abs(a - b) <= 1 for a, b in zip(box, state['initial'])), ('reversal did not restore frame', frames)
            result_path.write_text(json.dumps(dict(passed=True, frames=frames)))
            glfw.set_window_should_close(window, True)
            return
        pending = draw_state._pending_drags if axis == 'x' else draw_state._pending_row_drags
        pending.append((edges[1], edges[1][axis] + travel - state['travel'], True))
        state.update(stage=stage + 1, settle=3, travel=travel)
        Surface.active.request_frame()
    except Exception as error:
        result_path.write_text(json.dumps(dict(passed=False, error=repr(error), frames=frames)))
        glfw.set_window_should_close(window, True)


@meltygui.glfw_window(name='Native edge propagation check', app_id='native-edge-probe', width=800, height=800)
@render_func(use_cache=False, show_header=False, determines_height=False)
def check(input_value: object = None, draw_state=None, column_edges=None, row_edges=None):
    if axis == 'x':
        layout = ColumnLayout(draw_state, 2, column_edges=column_edges,
                              column_widths=[300., None], column_mins=[120., 200.],
                              column_maxes=[500., None])
    else:
        layout = RowLayout(draw_state, 2, row_edges=row_edges,
                           row_heights=[300., None], row_mins=[120., 200.],
                           row_maxes=[500., None])
    for index in range(2):
        with layout.cell(index):
            imgui.text('Column/row constraints reach native edges through Melty Windows.')
    layout.finish()
    window = Surface.active.window
    Melty.post_to_render(lambda: advance(window, draw_state, layout.edges))
    return False, input_value


meltygui.run()
