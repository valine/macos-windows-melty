"""App-owned resize reversals, with frame/callback timing and isolated app state."""
import json
import sys
import time
import ctypes
from pathlib import Path
import meltygui
from meltygui import imgui, window_api as glfw
from meltygui.core.melty import Melty
from meltygui.core.runtime import app
from meltygui.core.windowing.surface import Surface
from meltygui.core.windowing import titlebar, melty_windows

output = Path(sys.argv[1])
modal_only = '--modal-only' in sys.argv
moving_edge = '--moving-edge' in sys.argv
step = 32 if '--large' in sys.argv else 3
last_size = [1400, 900]
samples = []
original_frame = Surface.frame
original_refresh = app.refresh_surface
original_begin = melty_windows.begin_frame
native_groups = 0


def begin_frame(window):
    global native_groups
    frame = original_begin(window)
    native_groups += frame is not None
    return frame


melty_windows.begin_frame = begin_frame
objc = ctypes.CDLL('/usr/lib/libobjc.A.dylib')
selector = objc.sel_registerName
selector.argtypes, selector.restype = [ctypes.c_char_p], ctypes.c_void_p
live_selector = selector(b'inLiveResize')
send = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(('objc_msgSend', objc))


def refresh(surface):
    if not modal_only or send(glfw.get_cocoa_window(surface.window), live_selector):
        original_refresh(surface)


def frame(surface):
    began = time.perf_counter()
    groups_before = native_groups
    original_frame(surface)
    samples.append({'ms': (time.perf_counter()-began)*1000,
                    'native_group': native_groups > groups_before,
                    'callback': app._state.get('refreshing', False)})
    if len(samples) >= 180:
        output.write_text(json.dumps(samples))
        glfw.set_window_should_close(surface.window, True)


app.refresh_surface = refresh
Surface.frame = frame


def advance(window):
    # Same-magnitude steps, reversing each 15 frames. Native size changes
    # are queued at the same lifecycle boundary as the collision solver.
    index = len(samples) % 30
    travel = index if index < 15 else 30-index
    size = (1400 + travel*step, 900 + travel*step)
    offset = (last_size[0]-size[0], last_size[1]-size[1]) if moving_edge else None
    titlebar.request_surface_size(window, *size, offset=offset)
    last_size[:] = size
    Surface.active.request_frame()


@meltygui.glfw_window(name='Native resize timing probe', app_id='native-resize-timing', width=1400, height=900)
def check():
    for index in range(60):
        imgui.text(f'Native resize timing row {index}: reverse, resize, present.')
    window = Surface.active.window
    Melty.post_to_render(lambda: advance(window))


meltygui.run()
