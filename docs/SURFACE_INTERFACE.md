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
absolute path to its signed `MeltySurfaceFrame.dylib`. Since 0.2.2 it lives in
`Contents/Frameworks/SurfaceFrame-<build>/` so existing clients can load a new
helper without reopening their windows. Existing frame tokens finish through
their original helper. The C ABI remains version 1.
The adapter loads this helper in the cooperative app. `MeltySurfaceFrameBegin`
opens a zero-duration NSAnimationContext group on the main thread;
`MeltySurfaceFrameSet` applies content size and top-left displacement in one
native frame change with `display:NO`; `MeltySurfaceFrameEnd` closes the group
after the surface's GL buffer swap, including cleanup on render failure.
Native modal border resizing keeps its existing AppKit path. Older services
without the helper retain the GLFW setters. This groups geometry and buffer
submission; visual compositor synchronization still requires live acceptance.

The 0.2.2 helper also sets the native content view's layer placement to top-left
when beginning the first cooperative frame, before any resize. AppKit's default scales the currently presented
image to the new frame even when the new NSGL buffer has not arrived. Keeping
the image at its original pixel scale removes this intermediate stretch. The
placement persists beyond the animation group because presentation happens
asynchronously. This introduces no settling timer, blocking GPU wait, or change
to collision/input rules. [AppKit layer placement](https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement-swift.property)

The reference adapter is `meltygui/core/windowing/melty_windows.py`, wired
through `titlebar`, `os_frame`, and `window_api`. Client applications need no
new API calls. Ordinary app size requests stay separate from collision requests.
When capability is lost, the existing fixed-bound transition resets pending
collision requests and their child compensation before rendering. Reconnection
starts new gesture bookkeeping. Fullscreen/maximized/nonresizable surfaces
remain fixed; no arbitrary OS-window repulsion is authorized.

## Native background movement

Version 0.2.3 optionally advertises `move_api:1` and `move_enabled:true`
alongside `frame_library`. Movement requires the same live per-surface lease
and the utility's left-move setting; older services/helpers remain supported
without this optional capability. No screen recording is needed for this path.

The app captures its original Cocoa left-mouse-down event inside the GLFW
button callback with `MeltySurfaceMoveCapture(window, down)`. Its existing
input routing gives controls, text, dividers, movable Melty windows and fixed
popovers their normal priority. Only the lowest-priority, unclaimed native
background target calls `MeltySurfaceMoveBegin(window)`. OS decorations do not
disable this background target. The helper consumes the saved press once,
rejects released/nonmovable/fullscreen windows, and hands that same event to
[AppKit's native window move](https://developer.apple.com/documentation/appkit/nswindow/performdrag(with:)).
The call returns immediately. Since WindowServer may consume mouse-up, the
helper posts a release to the app's own window to clear GLFW and MeltyGUI input
state. It never posts desktop input or moves another process's windows.

Native geometry and rendering continue through the existing surface lifecycle;
no position stream or synchronous mouse-event IPC is added. The utility keeps
passing the full input sequence through for registered surfaces.

`Diagnostics/SurfaceMoveTests.m` tests original-event identity, per-window
isolation, release delivery, stale-press refusal and rapid regrab, using real
AppKit objects with an intercepted native handoff. `Diagnostics/native-background-move.py`
is the isolated interactive acceptance fixture: drag its striped background,
then its orange control. The JSONL records native origin/size, handoff success,
button state and control edits. Physical drag acceptance remains distinct from
the mocked handoff and input-routing tests.

On October 5 the signed 0.2.3 build 20 was installed with this optional move
API. All 53 Swift tests, the native frame/move checks, and 117 focused MeltyGUI
tests against a noneditable wheel passed. The wheel checks include adding
pointer-safe move exports to an already-cached helper during hotswap. The
installed helper also passed the 300-frame resize presentation probe: 588
captures, zero stretching mismatches and zero marker-origin movement. Physical
background/control drag acceptance is still pending; the desktop automation
did not hold macOS's physical button state through a render frame.

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

The Cocoa adapter also supplies the applied window origin to MeltyGUI's
existing drag compensation. A window moving under the cursor must not count
as hand movement. `Diagnostics/native-drag-motion.py` checks real helper-driven
native movement against stationary and independently moving drag samples,
without sending desktop mouse events. `Diagnostics/native-fractional-collision.py`
checks rendered column/row shrinking, holding and reversal at fractional steps.
These exposed two shared reconciliation errors: the pinned body truncated a
size that the native request rounded, and a rounded acknowledgement could be
replayed as an external native-edge drag. Both have regressions on simulated
feed and Cocoa backends; the underlying collision rules are unchanged.

Rapid release/regrab is tracked by input press identity, including when no
rendered frame observes the released state. Cocoa pointer compensation,
divider totals, native/layout replay snapshots and diagnostic history must
start from the new press. A queued old release must not clear a newer press's
coordinates. The native drag probe also covers this between-frame regrab.

The later endpoint-rounding, cache gesture-boundary and resize-settling changes
were rolled back at Lukas's request after the visible jitter persisted and
left/top pushes snapped. `Diagnostics/native-boundary-resize.py` retains the
isolated fractional screen-wall case as a diagnostic; its earlier passing
result did not establish a fix for the reported visual jitter.

The input-only fixes were subsequently restored after the release/regrab delay
returned: cooperative Cocoa callbacks no longer start the 150 ms native-resize
settling tail, settling state belongs to each surface, and cached resize replay
lets press/release events reach their receivers and cached ancestors. Unrelated
tiles can still use cached replay. Endpoint-rounding and collision geometry
changes remain rolled back; restoring input delivery does not establish a fix
for single-frame stretching.

The October 5 trace from editor process 93386 records ten transitions to
`(-1, -1)` while a right-button resize remains held. At frame 11161 this
changes the requested height from 1180 to 643; later samples incorporate
the native origin shift into that unavailable pointer value and repeatedly
push the left edge. The GLFW imgui backend uses this value when unfocused.
The shared collision solver should not be changed to accommodate it. The
Mac input/gesture ownership path and the pending-frame row-position reports
remain unresolved; diagnostics stay enabled.

## Presented-pixel regression

`zsh Diagnostics/test-native-presentation.sh /absolute/python /tmp/capture-output`
captures only its own diagnostic window using ScreenCaptureKit's current-process
enumeration; it does not capture other apps or inject desktop input. An optional
third argument selects a candidate `MeltySurfaceFrame.dylib`. The probe runs the
real MeltyGUI render pipeline through 300 grow/shrink frames, moving the top/left
edges, and stamps a 200px square at a fixed content position into the final back
buffer. Captured dimensions and origin must remain constant. The JSONL and
summary are retained in the output directory. App state is isolated there too.

On October 5 the persisted regression against the old helper produced 375
stretched captures out of 562 and 20px/23px marker-origin movement. Moving the
placement setup before the first resize also fixed a startup-only mismatch
caught by the noneditable-wheel check. The final signed build 19 passed two
300-frame runs with that wheel (503 and 629 captures), with zero size mismatches
and zero marker-origin movement. The installed-helper run averaged 14.0 ms
(95th percentile 16.3 ms). Editor process 4203 was confirmed to have loaded the
build 19 helper while retaining its previous helper mapping. These are
presented-pixel checks on this Mac, not just solver geometry assertions;
physical-gesture acceptance and the other collision warnings remain separate
checks.
