"""Run with the meltygui environment and an absolute SurfaceBridgeProbe executable."""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time

from meltygui.core.windowing import window_api as glfw, melty_windows as bridge, titlebar

with tempfile.TemporaryDirectory(prefix='melty-bridge-', dir='/tmp') as directory:
    bridge.PATH = directory + '/surfaces.sock'
    process = subprocess.Popen([os.path.abspath(sys.argv[1]), bridge.PATH],
                               stdout=subprocess.PIPE, text=True, close_fds=False)
    assert process.stdout.readline().strip() == 'ready'
    assert glfw.init()
    glfw.window_hint(glfw.CLIENT_API, glfw.NO_API)
    glfw.window_hint(glfw.FOCUSED, False)
    window = glfw.create_window(480, 320, 'Melty surface bridge test', None, None)
    try:
        number = bridge._window_number(window)
        assert number > 0
        assert bridge._exchange({number})
        assert not bridge.available(window)  # Discovery is asynchronous.
        deadline = time.monotonic() + 1
        while not bridge.available(window) and time.monotonic() < deadline:
            glfw.poll_events()
            time.sleep(.01)
        assert titlebar.can_adjust_window_edges(window)
        initial = bridge.observe(window)
        bridge.apply(window, 500, 340, (12, 15))
        observed = bridge.observe(window)
        assert observed[0] == (initial[0][0] + 12, initial[0][1] + 15), observed
        assert glfw.get_window_size(window) == (500, 340)
        # A client cannot claim another process's native window (or an invented ID).
        try:
            bridge._exchange({0xFFFFFFFF})
        except (OSError, ValueError):
            pass
        else:
            raise AssertionError('invalid native window was accepted')
        deadline = time.monotonic() + 4
        while bridge.available(window) and time.monotonic() < deadline:
            glfw.poll_events()
            time.sleep(.02)
        assert not bridge.available(window), 'pause failed to revoke capability'
        print('PASS: authenticated socket, automatic discovery, native content geometry, resize/move, invalid-window rejection, pause fallback')
        print('Native geometry:', initial, '->', observed)
    finally:
        glfw.destroy_window(window)
        glfw.terminate()
        process.terminate()
        process.wait(timeout=2)
