# Melty Windows

A native macOS menu-bar prototype for the outer-window gestures in MeltyGUI and
Lukas's Hyprland HDR fork. Requires macOS 26 or later and the Swift command-line tools.

## Run

```sh
./scripts/build-app.sh
open "dist/Melty Windows.app"
```

Keep the app in one location before granting permissions. In its Settings window,
grant **Accessibility** for moving/resizing and mouse interception, and
**Screen Recording** for left-click background detection. The app shows the exact
permission state. macOS may require quitting and reopening after a capture grant.
Development builds now reuse a local **Melty Local Development** signing
certificate. macOS can match successive builds to the same permission identity
instead of the binary hash used by ad-hoc signing. The first migration from an
old ad-hoc build may need one more Accessibility and Screen Recording grant;
ordinary rebuilds should retain them afterward. This is not a notarized
distribution build.

The build script automatically creates the certificate once, signs the helper
first, and then signs the app. Keep `org.melty.windows` and the installed app
location stable. Quit the running app before replacing its bundle, then reopen
the installed copy. Do not run `tccutil reset` as part of rebuilding.

The identity lives outside the project at
`~/Library/Application Support/Melty/DevelopmentSigning`. Preserve that directory
in your private backups: deleting or replacing it creates a different identity.
It contains a dedicated keychain, its automation password, the public certificate,
and its fingerprint; access is restricted to your user. The private key is
imported as non-extractable and its temporary export is deleted. The certificate
is valid for ten years; expiry requires deliberate migration. No trusted root,
Apple developer account, administrator access, or changes to SIP/TCC are needed.
Missing or mismatched signing state fails the build instead of silently creating
a replacement identity or falling back to ad-hoc signing.

Other local app projects can reuse `scripts/sign-dev.sh "path/to/Your App.app"`
as their final build step. Give each app its own stable bundle identifier and
sign nested helper apps before their containing app. This helper handles app
bundles; projects with frameworks or other nested executable formats should
integrate the same identity into their own build system. Each app still needs
its own initial permission grants. macOS can also require renewed consent for
reasons independent of rebuilding, including OS-managed screen capture reminders.

On this Mac, `~/.local/bin/melty-sign-dev` links to that script, so another
project's build can finish with:

```sh
~/.local/bin/melty-sign-dev "path/to/Your App.app"
```

`scripts/test-signing.sh` compiles two different binaries and verifies that
macOS accepts the second under the first one's designated requirement. It also
checks that another bundle ID and an ad-hoc replacement cannot match that
identity. This tests identity continuity; live permission grants still come
from System Settings.

Live verification on October 4, 2026: after the one-time migration grant, added
bundle path/identifier output to `--diagnostics`, rebuilt a different executable,
quit the app, replaced the installed bundle at
`~/Applications/Melty Windows.app`, and reopened it. Both Accessibility and Screen
Recording remained **Granted**, with status **Ready**, without another grant.

See Apple's [code signing identity documentation](https://developer.apple.com/library/archive/technotes/tn2206/)
for the designated requirement mechanism and self-signed development identities.

Use the menu-bar icon to pause, exclude the last active app, open settings, open
a separate test window, or quit. Hold **Option before pressing** to bypass the
gestures. **Escape** cancels an active gesture and restores its initial geometry.
No login item is installed.

## Behavior selected for this app

Lukas's October 3 clarification chooses Hyprland's corner selection instead of
Melty's right/double-right gesture distinction, and adds Hyprland's solid-background
left-drag detection. The original repositories are reference inputs, unchanged.

| Behavior | Implementation |
| --- | --- |
| Right-drag corner | The press selects left if it is within `min(400 pt, 30% of width)` of the left edge, and top within `min(400 pt, 30% of height)` of the top. Else right/bottom. The corner stays fixed through the gesture. Band 0 selects by the midpoint. |
| Right click | Hold the press while resolving intent. Below an 8 pt drag threshold, replay the normal click, retaining click count, modifiers and timestamp. |
| Left-drag background | Check app exclusions, available cursor hotspot, AX hit roles/ancestors, and browser toolbar dead zones. Capture a square around the original press, shifted inside the window. Every RGBA channel must be within tolerance of the pixel under the press. |
| Saved Hyprland pixel settings | Radius **52 logical points** (105 × 105 at scale 1); per-channel tolerance **29 / 255**. These come from `config/settings.lua`, overriding the 8 / 3 defaults in `config/hyprland.lua`. Native display scaling is applied before sampling. |
| Left click vs. move | After background detection, move tentatively with the pointer. Crossing 12 pt commits. A short click restores tentative geometry, then replays the click. |
| Move limits | Clamp the top to the current display's usable top. Other edges may extend offscreen, subject to the target app/macOS. |
| Resize limits | Collide with all usable display edges. Overflow grows the opposite side until the display is filled. Includes menu bar and Dock reservations, without copying Hyprland's separate 24 px Linux dock margin. |
| Sticky reversal | Solve every sample from the press snapshot, not from previously clamped geometry. Reverse to undo displacement, with no growth from stationary samples. |
| Min/max sizes | Let the target app accept or constrain its requested size, then use that accepted size to push/pull the opposite edge. Reject a minimum larger than the usable display instead of silently violating it. |
| Continue at cursor edge | Use relative event deltas when the visible cursor is clamped; never warp the cursor. Device-dependent acceleration and reversal need live verification. |

Popups, nonstandard/modal/fullscreen windows, sheets, and unsettable window
attributes pass through. A candidate must match both the public Accessibility
window and the topmost WindowServer window at the press. No arbitrary window
repulsion, tiling, or sibling collision is introduced.

## Review of the source repositories

The governing Melty document is
[`WINDOW_COLLISION_COLUMNS.md`](../meltygui/docs/WINDOW_COLLISION_COLUMNS.md).
Its outer-window wall/resize/reversal requirements transfer to this app. Its
columns, rows, nested Melty windows, native containment, and minimum/maximum
cascades operate on an internal layout graph. A system-wide utility cannot
recover that graph or apply those internal behaviors to every macOS app.
Melty Code Editor is excluded by default so its own layout gestures retain ownership.
The automatic surface integration below now enables the existing MeltyGUI layout
solver to adjust native edges on macOS without exposing its layout graph.

The copied Hyprland repository contains the tracked compositor **patch**, not
the original out-of-tree full source/build. The relevant code is in
[`hyprland-0.56.2-hdr-desktop.patch`](../hyprland-hdr/patches/hyprland-0.56.2-hdr-desktop.patch):

- `InputManager::rightDragResizeMotion`, around line 4235: threshold and 30% corner bands.
- `InputManager::leftDragMovePixelsUniform`, around line 4395: shifted crop, native scale,
  every-channel comparison with the pointer pixel, failure means no takeover.
- `InputManager::leftDragMoveArm`, around line 4517: cursor/exclusion/dead-zone gates,
  held-click immediate movement when `left_drag_move_detect` is off.
- `DragController::pushResizeAxis`, around line 2246: wall contact and opposite-edge expansion.
- `PointerManager::move`, around line 5583: virtual pointer continuation at a display edge.

The comments describing “nearest corner” and “small windows split at center” are
less precise than the actual 30% implementation. The late `config/settings.lua`
overrides also matter; copying only defaults would produce different background detection.

## MeltyGUI integration (0.2.0)

Apps using the updated sibling `meltygui` library discover Melty Windows
through its shared windowing layer. No app registration code or bundle-ID
exclusion is needed. Run the updated utility with Accessibility granted and
Enabled on. Existing apps need the updated library loaded; packaged apps must
include that version of MeltyGUI. Older library builds cannot discover this interface.

MeltyGUI owns column/row gestures, min/max propagation, native containment,
and sticky reversal. Melty Windows yields input for each registered native
surface, so an inner right-drag does not turn into an outer corner resize.
The app applies native geometry before its next render pass, using its own GLFW
window rather than Accessibility IPC. Ordinary apps retain the existing behavior.
The native title bar remains native; its size is reserved at display boundaries.
Coordinates are logical points, not Retina framebuffer pixels.

Pause, loss of the utility, or an expired agreement returns the app to its
existing fixed-bounds fallback and discards pending collision compensation.
Automatic discovery/reconnection runs off the render thread. Maximized,
fullscreen, and nonresizable windows do not enable native edge adjustment.
No collision between separate OS windows is introduced.

The versioned [surface interface](docs/SURFACE_INTERFACE.md) is deliberately
small: a process claims its own native surfaces; the service acknowledges gesture
ownership. Geometry, constraints, and the layout graph remain app-owned.

Validation: Swift ownership/expiry tests; MeltyGUI adapter and existing layout
regressions; a native GLFW/Swift socket probe for discovery, actual geometry,
invalid-window rejection and pause fallback. These do not establish visual
Hyprland parity, physical gesture routing under every app, or mixed-display
behavior; those remain live acceptance checks.

## macOS architecture and limits

- A public [CGEvent event tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))
  intercepts eligible mouse sequences. AX resolution and capture run outside its
  callback. Unresolved candidates time out after 180 ms and replay their buffered input.
- [Accessibility attribute writes](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)
  move/resize the chosen window. One transaction runs at a time; pending movement
  is replaced with the latest sample. Position and size are separate writes,
  not an atomic compositor operation. Ordinary resizing writes the final size
  once. Probe its accepted size at the current origin, then position the accepted
  frame. Only pre-position axes where growth needs more display space. This keeps
  compression past an app minimum from jumping between an unconstrained origin
  and the final pushed origin. Restoration chooses the order that fits the
  display, using an intermediate size only when neither order fits. Round target
  edges to logical points and skip unchanged attributes. Position and size
  readbacks share one AX query, and changing readbacks are not used as size limits.
  AX-unresponsive apps can decline a gesture.
- During a resize gesture, suspend `AXEnhancedUserInterface` if it was enabled
  and restore it after completion, failure, or quit. This avoids AppKit animating
  successive AX writes, a workaround also used by
  [Rectangle](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityElement.swift)
  and [yabai](https://github.com/asmvik/yabai/blob/master/src/window_manager.c).
  The attribute is optional and undocumented; failed reads/writes leave normal
  resizing available. It is left untouched when VoiceOver or Switch Control is on.
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)
  captures only a transient visible-screen crop, with the cursor excluded and SDR
  output converted to sRGB RGBA. Samples never go to disk. Crops obscured by another
  window are declined. This is not Hyprland's private window framebuffer; capture
  latency, translucency and HDR color conversion can change classification near
  the tolerance boundary. Protected content may not be capturable.
- Apple's [global cursor API is deprecated](https://developer.apple.com/documentation/appkit/nscursor/currentsystem).
  When it returns a cursor, the prototype applies Hyprland's top-left hotspot
  heuristic. When unavailable, AX controls plus pixels supply the gate. This
  cannot perfectly classify custom canvases, games or inaccessible controls;
  use per-app exclusions or Option bypass for those apps.
- macOS controls window redraw timing, native window constraints, Spaces and
  fullscreen. This app cannot reproduce Hyprland's renderer changes (frozen
  textures, damage scheduling, vblank coordination), guarantee 120 Hz movement,
  or globally alter another app's inner rows and columns.

## Validation

```sh
./scripts/test.sh
./scripts/test-signing.sh
./scripts/build-app.sh
"dist/Melty Windows.app/Contents/MacOS/MeltyWindows" --diagnostics
```

The 41 Swift Testing tests exercise corner selection, all display walls,
opposite-edge growth/reversal, min/max propagation, move limits, shifted pixel
crops, exact tolerance/alpha/row-stride checks, latched intent, virtual-pointer
motion, and resize invariants across thousands of deltas on a negative-origin
display. Two window-stack regression cases cover the Dock's full-screen layer 20
surface (which initially caused every target to be rejected) and a real app
window overlapping a pixel sample. Frame-transaction regressions model native
setters that clamp growth to the room at the current origin: bottom contact,
all four corners, full-display growth and reversal, mixed shrinking/growth,
app min/max limits, size reanchoring, display changes, and refused writes.
Flicker regressions verify that ordinary diagonal dragging presents only its
final shape, fractional motion does not repeat writes, wall pushing still works
without extra corrections, and animated readbacks do not move the opposite edge.
Animation-scope tests cover restoration and preserving assistive-technology use.
The recorded Safari 574 pt minimum-width case checks every intermediate position
through continued compression and reversal; all corners and native size increments
are covered so a size step cannot get stuck as a permanently cached minimum.
These are backend/geometry/pixel/window-selection tests, not proof of cross-app
input behavior. The test script explicitly loads
the bundled Swift Testing macro plugin to work around an incremental-build
issue in this Mac's Swift 6.4 command-line tools.

Only one utility instance can run, including when launching another copy from
`dist`. The test window has its own helper-app identity. Diagnostic builds write
bounded event/geometry logs to `~/Library/Logs/Melty Windows.log`; no screen
pixels, window titles, typed text, or passwords are logged.

Live acceptance requires granting this app macOS permissions. In the separate
test window and then Safari/Finder/other target apps, verify:

1. All four corner bands, short right clicks/context menus, and double-clicks.
2. Flat background movement; text selection, buttons, scrollbars, and app exclusions.
3. Tiny left movement returns a normal click, including rapid second clicks/chords.
4. Every resize wall, opposite-edge expansion, stationary holds, full reversal,
   app minimum sizes, and Escape restoration.
5. Different display origins/scales, menu bar/Dock reservations, and pointer
   continuation/reversal at physical display edges.
6. Closing the target during a drag, delayed/failed capture, app hangs,
   permission changes, and pausing/quitting without a stuck button.

After granting Accessibility and Screen Recording, Lukas reported that movement
and resizing work, with display-edge pushing still failing. Version 0.1.1 fixes
the frame-write ordering. With the updated app running and both grants restored,
live Safari readbacks showed a bottom-right resize keeping the bottom at 1728 pt
while the top moved from 391 pt to 243 pt and the height grew from 1033 pt to
1485 pt. Reversal also reduced that growth. All four edges are covered by the
backend regressions; live verification across all apps/displays remains open.
Lukas then reported flicker and a jelly-like appearance. Version 0.1.2 removed
unnecessary intermediate sizes and scoped the Enhanced UI workaround to resizing.
Live logs subsequently identified two position writes per sample while Safari
was held at its 574 pt minimum width. Version 0.1.3 probes size before applying
the final constrained position, removing that repeated snap-back. Settings status
also publishes only when it changes, rather than redrawing for each mouse sample.
Lukas confirmed that this revision works substantially better. Version 0.1.4
fixes Safari background dragging: its outer AXTabGroup contains the whole web
page and must not be treated as an interactive tab widget inside the page.
Regression tests use the observed Safari ancestor chain and retain protection
for links, controls, and tab widgets within web content. Ancestor walks allow
deeper page layouts and log the specific rejected roles for diagnosis.
There is no delayed cursor-change/drag-skip detection: the cursor heuristic
runs only at the initial press, matching the saved Hyprland detect=false mode.
The 180 ms deadline is a fail-open limit for AX/pixel resolution, not a cursor
grace period.
Version 0.1.5 resolves missing AXWindow attributes through the hit element's
parents. Settings detail-pane right-drags also allow a unique window belonging
to the hit app and containing the press when its parent chain is detached.
The normal window eligibility and topmost WindowServer geometry checks still
apply; no focused-window substitution is used. This addresses recorded
AXStaticText hits in Settings' right pane returning no AXWindow. Live right-drag
validation is still required because the UI automation tool supports left drag only.
Version 0.1.6 adds readback verification for size writes returning AXCannotComplete:
continue only if the observed size reached the request or measurably moved toward
it. Unchanged, unavailable, or unrelated geometry still fails. Two regression
tests cover applied/clamped writes and refused/invalid readbacks. This addresses
a suspected acknowledgment failure in Music; the exact AX errors and transaction
failures are now logged, and live Music confirmation is pending.
The 0.1.6 live logs confirmed AXCannotComplete (-25204): Music applied the
requested size, but sometimes both the setter and verification read timed out,
cancelling the gesture after about 123 ms. The next gesture observed the exact
previously requested size. Version 0.1.7 gives active resize transactions a
500 ms per-message reply budget on the AX worker queue, restoring 40 ms after
each transaction. This is a maximum wait, not an artificial delay. Initial
hit-testing and left-drag movement keep the short timeout.
Adaptive pacing measures AX transaction duration (not private render frames).
Two responses at least 50 ms, or one at least 100 ms, enable slow mode. It adds
16–100 ms recovery time, based on half the smoothed response duration, after each
completed resize. Only the latest pointer sample is retained. Mouse release
bypasses that recovery delay to drain the final sample, and cancellation clears
scheduled work. Eight responses below 25 ms restore normal pacing. The learned
state is remembered per app process for this utility session. Three tests cover
fast apps, recorded Music timings, bounded waits, and recovery hysteresis.
Live Music acceptance of adaptive pacing remains pending.
Version 0.1.8 corrects request selection during worker delays: the worker takes
the newest pending geometry after queue waiting and the initial animation-scope
AX call, instead of retaining the request captured at dispatch time. Samples
arriving during the actual transaction remain queued for its successor. Tests
cover queue delays, an in-flight write, cancellation, and restoration.
This removes one source of stale writes; it is not yet verified as a fix for
the single-frame content stretching reported in Melty and Blender.
The standalone GLFW probe in Diagnostics reproduced the reported stretching.
Its baseline trace recorded 133 external size callbacks with no discrepancy
between native content bounds, GLFW window/framebuffer dimensions, and draw
dimensions. Some replacement buffers were submitted about 12 ms after the size
callback. The immediate-redraw variant is experimental and does not modify
the installed utility or third-party apps.
Neither a Linux compositor nor GPU parity was run or claimed on this Mac.

Version 0.1.9 adds an opt-in **Native live resize (experimental)** setting to
test the actual macOS resize path. After the existing hit test, corner selection,
and drag threshold, the event tap translates right-button motion into left-button
events at the selected corner. Ordinary native resizing makes no AX size writes.
This tests the important difference seen in the probe: native edge callbacks have
`inLiveResize = true`, while AX setters leave it false even with correct sizes.
The event-redirection approach is also used by AnyDrag's current ResizeStrategy:
https://github.com/XueshiQiao/AnyDrag/blob/main/AnyDrag/Sources/ResizeStrategy.swift
Our route and gesture integration are implemented independently.

The experiment is not a confirmed jelly fix. At display overflow (or crossing the
opposite edge), it ends the native drag and hands the remainder of that gesture
to the original collision solver, using the original press geometry and total
delta. This preserves display-edge pushing but may reintroduce stretching there.
Before handoff, native minimum-size behavior applies, rather than our minimum-size
push behavior. Escape closes the native drag and restores through the AX writer.
The toggle defaults off; turning it off restores the existing resize behavior.
Four geometry tests cover event anchoring, reversal, collision handoff on all
edges, and negative-origin displays. Physical right-drag visual validation is
required; unit tests cannot establish WindowServer presentation behavior.

Version 0.1.10 removes the blanket gesture exclusion for the utility's own
process. The settings window now has the resizable style and flexible content,
with a 520 × 440 pt content minimum. Its controls still use the same background
hit policy as other apps. Own-window writers skip the external Enhanced UI
override and its synchronous quit-time restoration, avoiding self-IPC waits.
The signed build and native-edge expansion of the settings content were checked;
physical left/right gesture validation is separate from this UI check.

Version 0.1.11 fixes the self-window crash introduced in 0.1.10. Crash reports
showed AppKit's main-thread assertion in both accessibilityPerformRaise and
AX position setters: self-targeted AX invokes AppKit on the calling thread.
Own-window resolution, raising, frame transactions, and capture-time geometry
verification now use the main queue; external targets retain the serial IPC
worker. Resolution conservatively selects main inside visible own-window bounds
and rechecks the resolved PID before accessing attributes. Two regression tests
execute queued work and verify main-thread affinity for self and worker affinity
for external targets. All 47 tests pass. Physical gesture retesting remains
necessary because UI automation does not exercise our global right-drag tap.

The 0.1.12 corner-switching experiment was rejected and rolled back after live
reports of target leakage and incorrect sizes. The proposed 0.1.13 routing change
was never deployed. Neither is in the current source. Rejected source is retained
in /tmp/melty-windows-rejected-source for diagnosis, not as a build input.

Version 0.1.14 tests a narrower change: a single native mouse-down at the original
corner remains held while the existing collision solver writes geometry. Native
mouse-up is deferred until the last write drains. No corner switching, additional
mouse-down, new hit test, or routing-metadata overrides occur during the gesture.
Failure and shutdown release the native button. A bounded size-grid learner
requires several distinct accepted sizes and a consistent rounding rule before
quantizing subsequent requests; one minimum/maximum plateau is not a grid.
Sparse fast-motion samples cannot establish an increment larger than their
observed rounding range. Grid-aligned requests avoid repeatedly moving the
window between cells at a wall. Existing minimum/maximum push tests still pass.

All 51 tests passed and the signed build launches with existing permissions.
The GLFW probe is back to its baseline redraw behavior, so its inLiveResize trace
can test the lifetime change without an app-side redraw workaround. Live
collision behavior and the visual result are not yet verified.
