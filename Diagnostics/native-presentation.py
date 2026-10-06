"""Measure presented pixels during actual MeltyGUI resizes, without desktop input.

Use test-native-presentation.sh to build the capture helper and isolate app state.
Optional final argument selects a candidate frame helper instead of the installed
one. A 200px marker at a fixed content position must keep its dimensions/origin.
"""
import ctypes
import json
import statistics
import sys
import time
from pathlib import Path

import meltygui
import OpenGL.GL as gl
from meltygui import imgui, window_api as glfw
from meltygui.core.windowing import titlebar, melty_windows
from meltygui.core.windowing.surface import Surface

capture_path, output_path, *candidate = sys.argv[1:]
output = Path(output_path)
capture = ctypes.CDLL(capture_path)
capture.MeltyPresentationStart.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
capture.MeltyPresentationStart.restype = None
for name in ('MeltyPresentationStop',):
    getattr(capture, name).argtypes = []
    getattr(capture, name).restype = None
for name in ('MeltyPresentationReady', 'MeltyPresentationStopped', 'MeltyPresentationFinish'):
    getattr(capture, name).argtypes = []
    getattr(capture, name).restype = ctypes.c_int
original_api = melty_windows._frame_api
if candidate:
    melty_windows._frame_api = lambda path: original_api(candidate[0])

original_swap = glfw.swap_buffers


def swap(window):
    _, height = glfw.get_framebuffer_size(window)
    # Stamp the final back buffer after MeltyGUI's complete render pipeline.
    gl.glEnable(gl.GL_SCISSOR_TEST)
    gl.glScissor(300, height - 500, 200, 200)
    gl.glClearColor(0, 1, 0, 1)
    gl.glClear(gl.GL_COLOR_BUFFER_BIT)
    gl.glDisable(gl.GL_SCISSOR_TEST)
    original_swap(window)


glfw.swap_buffers = swap
original_frame = Surface.frame
state = dict(started=False, frames=0, stopping=False, finished=False,
             last=(1400, 900), time=time.monotonic())
samples = []


def frame(surface):
    started = time.perf_counter()
    original_frame(surface)
    if state['finished']:
        return
    if not state['started']:
        capture.MeltyPresentationStart(glfw.get_cocoa_window(surface.window), str(output).encode())
        state['started'] = True
    ready = capture.MeltyPresentationReady()
    assert ready >= 0, 'Own-window capture unavailable'
    assert time.monotonic() - state['time'] < 30, 'Presentation probe timed out'
    if state['stopping']:
        if capture.MeltyPresentationStopped():
            result = capture.MeltyPresentationFinish()
            state['finished'] = True
            records = [json.loads(line) for line in output.read_text().splitlines()]
            positions = [record['square'][:2] for record in records]
            span = [max(p[axis] for p in positions) - min(p[axis] for p in positions) for axis in (0, 1)]
            report = dict(captures=len(records), mismatches=result, marker_origin_span=span,
                          frames=len(samples), mean_ms=statistics.mean(samples),
                          p95_ms=sorted(samples)[int(len(samples) * .95)])
            output.with_suffix('.summary.json').write_text(json.dumps(report, indent=2))
            print(report, flush=True)
            glfw.set_window_should_close(surface.window, True)
    elif ready and melty_windows.defer_refresh(surface.window):
        samples.append((time.perf_counter() - started) * 1000)
        index = state['frames'] % 30
        travel = index if index < 15 else 30 - index
        size = (1400 + travel * 24, 900 + travel * 18)
        offset = (state['last'][0] - size[0], state['last'][1] - size[1])
        titlebar.request_surface_size(surface.window, *size, offset=offset)
        state['last'] = size
        state['frames'] += 1
        if state['frames'] >= 300:
            state['stopping'] = True
            capture.MeltyPresentationStop()
    surface.request_frame()


Surface.frame = frame


@meltygui.glfw_window(name='MeltyGUI presentation check', app_id='melty-presentation-check', width=1400, height=900)
def check():
    for index in range(60):
        imgui.text(f'MeltyGUI frame presentation check {index}')


meltygui.run()
assert state['finished'], 'Probe closed before capture completed'
report = json.loads(output.with_suffix('.summary.json').read_text())
assert report['mismatches'] == 0, report
assert max(report['marker_origin_span']) <= 1, report
