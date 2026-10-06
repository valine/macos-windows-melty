"""Real native window motion with a stationary/screen-moving drag sample.

No mouse events or cursor warps are sent to the desktop.
"""
import time
from types import SimpleNamespace
from meltygui.core.windowing import window_api as glfw, melty_windows
from meltygui.core.graphics.overlay_renderer import SplitOverlayRenderer
from meltygui.core.input.input_handler import InputHandler
from meltygui.core.melty import Melty

assert glfw.init()
glfw.window_hint(glfw.CLIENT_API, glfw.NO_API)
glfw.window_hint(glfw.FOCUSED, False)
window = glfw.create_window(800, 600, 'Cocoa drag coordinate check', None, None)
try:
    deadline = time.monotonic() + 5
    while not melty_windows.available(window):
        assert time.monotonic() < deadline, 'surface capability missing'
        glfw.poll_events()
        time.sleep(.01)
    origin = glfw.get_window_pos(window)
    anchor = origin
    Melty.event_handler = InputHandler()
    Melty.event_handler.feed_down('right_mouse', 100, 100, t=10.)
    renderer = SimpleNamespace(window=window, _slide_screen_origin=None, _slide_native_sample=None)
    io = SimpleNamespace(mouse_down=[False, True, False], mouse_pos=(100., 100.))
    SplitOverlayRenderer._cancel_surface_slide(renderer, io)
    initial = io.mouse_pos
    for index, delta in enumerate([(-40, -25), (-40, -25), (30, 20), (50, 30)]):
        token = melty_windows.begin_frame(window)
        assert token is not None, 'installed helper missing'
        try:
            melty_windows.apply(window, 800, 600, delta)
        finally:
            melty_windows.end_frame(token)
        current = glfw.get_window_pos(window)
        # A fixed screen point acquires a new local coordinate when its window
        # moves. Later samples also include a small independent hand motion.
        hand = (0., 0.) if index < 2 else (10., -5.)
        io.mouse_pos = (initial[0]+origin[0]-current[0]+hand[0],
                        initial[1]+origin[1]-current[1]+hand[1])
        if index == 1:
            # UP/DOWN without a rendered released frame, after native motion.
            Melty.event_handler.feed_up('right_mouse', *io.mouse_pos, t=11.)
            Melty.event_handler.feed_down('right_mouse', *io.mouse_pos, t=12.)
            anchor = current
        SplitOverlayRenderer._cancel_surface_slide(renderer, io)
        assert io.mouse_pos == (initial[0]+origin[0]-anchor[0]+hand[0],
                                initial[1]+origin[1]-anchor[1]+hand[1]), io.mouse_pos
        glfw.poll_events()
    print('PASS: real Cocoa moves, stationary pointer, between-frame regrab and reversal')
finally:
    glfw.destroy_window(window)
    glfw.terminate()
