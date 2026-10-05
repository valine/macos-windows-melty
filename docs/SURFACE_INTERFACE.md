# Melty native surface interface, version 1

This interface lets a cooperative app keep its existing layout and gesture
model while Melty Windows supplies desktop gesture arbitration. It grants no
ability to manipulate another process's windows.

## Transport and discovery

Connect to the current user's Unix stream socket:

`~/Library/Application Support/Melty Windows/surfaces-v1.sock`

The parent directory is private (0700), the socket is 0600. The client checks
its type, owner and permissions. The server authenticates the peer UID/PID
from the kernel and checks every window ID against WindowServer ownership.
There is no caller-supplied PID, TCP port, subprocess or launch requirement.
The existing single-instance lock protects endpoint creation. A crashed
service's stale socket is replaced on the next launch.

Send one UTF-8 JSON object and newline, receive one JSON object and newline,
then close. Requests are bounded to 4096 bytes and 128 distinct window IDs;
read/write waits are bounded to 100 ms. Malformed/unsupported requests and
foreign windows close the connection without a grant.

Request (replaces this process's current surface set):

```json
{"version":1,"operation":"claim","windows":[123,124]}
```

Window numbers are WindowServer IDs (`NSWindow.windowNumber`), not GLFW or
NSWindow pointers. An empty set releases the process's claims while enabled.

Response:

```json
{"version":1,"capability":"native-edges","enabled":true,"lease_seconds":1}
```

`enabled:false` means fixed native bounds. True requires the utility to be
enabled with its event tap running in the active user session. New claims are
deferred while a mouse button is held, so ownership begins between gestures.
Clients refresh every 250 ms on a worker. A valid response grants only the
requested surfaces and expires one second after the request *started*, not
after the response arrived. Any transport/protocol error revokes the local
capability immediately. The server retains input pass-through for two seconds
after acceptance, giving the client time to stop native adjustment before
normal utility gestures can resume. Pause stops grants immediately; old claims
have the same bounded grace period. Close each surface through the shared
window API so the next heartbeat removes it. Termination stops the worker.

## Ownership and geometry

A registered app receives its normal mouse sequence, including short clicks,
column/divider drags and double-right drags. Melty Windows checks the native
window number on the press before creating a gesture; its AX resolution path
also checks the claim when an event has no usable window number. Ownership
stays with the original press for the rest of the sequence.

The app observes its content rectangle and usable display in the same
logical-point, top-left screen coordinate space used by GLFW input. Subtract
native frame insets from the display workarea, including titlebar height.
The app's existing edge solver produces requested content size and origin
changes. Apply both on the render thread before drawing, reconcile actual
native observations, and keep position/size compensation in the existing
surface lifecycle. Geometry never crosses this socket.

Version 0.2.1 optionally advertises `frame_api:1` and `frame_library`, the
absolute path to its signed `Contents/Frameworks/MeltySurfaceFrame.dylib`.
The adapter loads this helper in the cooperative app. `MeltySurfaceFrameBegin`
opens a zero-duration NSAnimationContext group on the main thread;
`MeltySurfaceFrameSet` applies content size and top-left displacement in one
native frame change with `display:NO`; `MeltySurfaceFrameEnd` closes the group
after the surface's GL buffer swap, including cleanup on render failure.
Native modal border resizing keeps its existing AppKit path. Older services
without the helper retain the GLFW setters. This groups geometry and buffer
submission; visual compositor synchronization still requires live acceptance.

The reference adapter is `meltygui/core/windowing/melty_windows.py`, wired
through `titlebar`, `os_frame`, and `window_api`. Client applications need no
new API calls. Ordinary app size requests stay separate from collision requests.
When capability is lost, the existing fixed-bound transition resets pending
collision requests and their child compensation before rendering. Reconnection
starts new gesture bookkeeping. Fullscreen/maximized/nonresizable surfaces
remain fixed; no arbitrary OS-window repulsion is authorized.

## Verification

`./scripts/test.sh` covers process/surface isolation, replacement, removal,
expiry and the existing outer-window geometry rules. MeltyGUI's
`test_melty_windows.py` covers the wire exchange, lease gating, native eligibility,
logical-point/inset conversion and pre-render application.

For actual native transport/geometry, run:

```sh
Diagnostics/test-surface-bridge.sh /absolute/path/to/meltygui/python
```

The script compiles the actual server/registry sources into `SurfaceBridgeProbe`
and runs `Diagnostics/test-surface-bridge.py` against it. The probe uses a
private temporary endpoint, opens a temporary GLFW window without focusing it,
and pauses after three seconds. It leaves the installed utility untouched.

Physical right/double-right gestures, complex nested layouts, movement between
displays/scales, service loss mid-drag, and visual presentation still require
live acceptance. Passing geometry tests does not claim compositor parity.

Verified on October 5, 2026: the signed 0.2.0 utility was installed and relaunched
at `~/Applications/Melty Windows.app`. Its running event tap granted the capability.
A noneditable MeltyGUI wheel installed outside the checkout passed all eight
adapter tests and used the installed service through `os_frame._observe` and
`titlebar.set_surface_size` to resize/move a real GLFW window. The isolated
server probe additionally verified pause and invalid-window rejection. No
physical right-drag or GPU presentation parity is claimed by these checks.

A real decorated MeltyGUI Surface also passed both axes of
`Diagnostics/native-collision-app.py`: compressing a column/row to its minimum
pushed the native near edge by 320 points and expanded the native span from
800 to 1120 points. Repeated stationary samples left geometry unchanged;
reversal restored the original 800-point span and screen origin. The check
queues local layout drag samples rather than synthesizing global mouse events.
Run it with a MeltyGUI Python interpreter, axis `x` or `y`, and an output JSON
path; use separate XDG state/cache/config and MELTY_FILE_META paths for the probe.

The signed 0.2.1 helper passed native combined-size/position, reversal and
transaction cleanup checks. Both rendered collision axes still passed. The
large-step resize benchmark confirmed helper use in all 161 measured frames,
averaging 10.4 ms (95th percentile 16.1 ms), with no recursive refresh frames.
These checks establish geometry and latency, not absence of visible stretching.
Re-run the native helper checks with `zsh Diagnostics/test-surface-frame.sh`.
