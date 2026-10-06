"""Fractional native-bound divider drag, hold and reversal on a real Surface.

Run with a MeltyGUI Python, axis x/y and output JSON; isolate XDG app state.
No global input is injected. Native setters/readback remain real.
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
from meltygui.core.windowing import os_frame, titlebar, melty_windows
from meltygui.core.windowing.surface import Surface

axis, result_path = sys.argv[1:]
result_path = Path(result_path)
Toggles.Melty.push_os_window_edges = True
Toggles.Melty.wayland_show_frame = True
os_frame._any_button_down = lambda: True
state = dict(start=time.monotonic(), index=0, previous=0.)
travels = [-i * 11.2 for i in range(1, 16)] + [-168.] * 3
travels += [-i * 11.2 for i in range(14, -1, -1)] + [0.] * 3
samples = []
original_apply = melty_windows.apply


def apply(window, width, height, offset):
    original_apply(window, width, height, offset)
    assert glfw.get_window_size(window) == (width, height), 'native size rejected'


melty_windows.apply = apply


def advance(window, ds, edges):
    try:
        if os_frame.mode() != 'cocoa':
            assert time.monotonic() - state['start'] < 5, 'Cocoa capability missing'
            Surface.active.request_frame()
            return
        if 'initial' not in state:
            state['initial'] = edges[1][axis]
            state['body'] = ds.width if axis == 'x' else ds.height
        value = edges[1][axis]
        body = ds.width if axis == 'x' else ds.height
        expected = state['initial'] + state['previous']
        samples.append(dict(frame=Melty.frame_count, divider=value, body=body,
                            expected=expected, native=glfw.get_window_size(window)))
        # The rendered layout snaps its handles to logical pixels.
        assert abs(value - expected) < 1., samples[-1]
        assert body == round(state['body'] + state['previous']), samples[-1]
        if state['index'] == len(travels):
            result_path.write_text(json.dumps(dict(passed=True, samples=samples)))
            glfw.set_window_should_close(window, True)
            return
        travel = travels[state['index']]
        pending = ds._pending_drags if axis == 'x' else ds._pending_row_drags
        pending.append((edges[1], value + travel - state['previous'], True))
        state.update(index=state['index']+1, previous=travel)
        Surface.active.request_frame()
    except Exception as error:
        result_path.write_text(json.dumps(dict(passed=False, error=repr(error), samples=samples)))
        glfw.set_window_should_close(window, True)


@meltygui.glfw_window(name='Fractional native collision check', app_id='fractional-native-probe', width=1000, height=1000)
@render_func(use_cache=False, show_header=False, determines_height=False)
def check(input_value: object = None, draw_state=None, column_edges=None, row_edges=None):
    if axis == 'x':
        layout = ColumnLayout(draw_state, 2, column_edges=column_edges,
                              column_widths=[None, 300.], column_mins=[60., 60.],
                              column_maxes=[None, 300.])
    else:
        layout = RowLayout(draw_state, 2, row_edges=row_edges,
                           row_heights=[None, 300.], row_mins=[60., 60.],
                           row_maxes=[None, 300.])
    for index in range(2):
        with layout.cell(index):
            imgui.text('Fractional drag: native request and body must agree.')
    layout.finish()
    window = Surface.active.window
    Melty.post_to_render(lambda: advance(window, draw_state, layout.edges))
    return False, input_value


meltygui.run()
