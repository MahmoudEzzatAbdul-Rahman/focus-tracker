# FocusTracker

Look at a window, tap **left ⌃ (Control)**, and that window gets keyboard focus, so you can type into whatever you're looking at without reaching for the mouse.

FocusTracker is a macOS menu-bar app that estimates your gaze from a webcam using Apple's Vision framework. It outlines the window you're looking at, and focuses it when you tap the hotkey, or, in dwell mode, once you've kept looking at it for a moment.

> **Accuracy:** webcam gaze estimation is good to a few centimeters on screen. That's enough to tell tiled windows apart (halves, thirds, quadrants), but not small overlapping windows.

## Requirements

- macOS 14 or later, Apple silicon
- A webcam. An external one mounted at the top center of the display works best.
- Swift 6 toolchain. Command Line Tools are enough; Xcode isn't needed.

## One-time setup: signing identity

macOS remembers Camera and Accessibility grants per code signature. An ad-hoc signed build gets a new signature on every rebuild, which means re-granting Accessibility every time. A self-signed certificate avoids that:

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `FocusTracker Dev`, Identity Type: **Self Signed Root**, Certificate Type: **Code Signing** → Create.

`scripts/build-app.sh` uses that identity automatically. You can use a different one with `SIGN_IDENTITY="…"`. Without it, the script falls back to ad-hoc signing and prints a warning.

## Build and run

```sh
./scripts/build-app.sh          # → build/FocusTracker.app
open build/FocusTracker.app
```

On first launch:

1. **Camera:** allow when prompted.
2. **Accessibility:** needed to see the hotkey and to focus other apps' windows. Enable FocusTracker under *System Settings → Privacy & Security → Accessibility*. The app picks up the grant within a couple of seconds, with no relaunch needed.
3. **Calibrate:** click the 👁 menu-bar icon → **Calibrate…**. Look at each dot as it appears, sitting as you normally do. A dot turns green while it's being sampled. The whole run takes about 30 seconds, and **Esc** cancels. The average error on separate validation dots is shown at the end and in the menu.

Screen Recording permission is **not** needed; only window positions are read, never their contents or titles.

## Usage

- A blue outline marks the window you're looking at. It moves to another window after your gaze has stayed there for 250 ms, so quick glances are ignored.
- Pick how the outlined window gets focus under **Focus Mode**:
  - **Tap Left ⌃** (default): tap left ⌃ (Control) on its own, press and release within 350 ms. You hear a beep when there's no target.
  - **Look (Dwell)**: the outlined window gets focus automatically once you've kept looking at it for the **Dwell Time** (0.5–2 s, default 0.8 s). Each look focuses a window only once, so clicking elsewhere doesn't make it grab focus back until you look away and return. Tapping left ⌃ still focuses right away.
- Using left ⌃ as part of a shortcut (for example ⌃C in Terminal) or a ⌃-click never triggers a switch. Caps Lock doesn't interfere.

Menu items:

| Item | What it does |
|---|---|
| Enabled | Pauses or resumes tracking. The camera is off while paused. |
| Focus Mode | Tap Left ⌃ or Look (Dwell), plus the dwell time. |
| Calibrate… / Recalibrate… | Runs calibration. Recalibrate if you change your seat, the camera position or the lighting. |
| Camera | Picks the camera to use. |
| Show Gaze Dot | Shows the estimated gaze point as a red dot. Useful for judging accuracy. |
| Use Mouse as Gaze | Debug mode: the mouse cursor stands in for your gaze, and the camera stays off. |
| Show Debug Window | Opens a camera preview and live head-pose/pupil values. Use it to check the camera framing. |

## Tips for accuracy

- Put the camera at the top center of the screen, at roughly eye height, with your face well lit from the front.
- Recalibrate after moving your chair, or when the gaze dot drifts noticeably.
- It's fine to turn your head a little toward the window you want. Head pose is the strongest signal, and calibration learns how your head and eyes move together.
- Check the calibration error in the menu. Under about 200 pt is good for a 2–3-way split on a large display.

## How it works

```
Camera (AVFoundation, 640×480)
  → FaceFeatureExtractor   Vision face landmarks: head yaw/pitch/roll, pupil position
                           inside each eye, face position/size in the frame
  → GazeModel              ridge regression on polynomial terms, fitted during calibration
  → PointFilter            One Euro filter: smooth while still, responsive on big moves
  → TargetSelector         topmost window under the gaze point, with a 250 ms dwell
  → DwellTrigger           dwell mode only: focus once the outline has held for the dwell time
  → HighlightOverlay       click-through outline on top of everything
HotkeyMonitor (left ⌃ tap) → WindowFocuser (Accessibility API: frontmost app + raise window)
```

- `Sources/GazeCore` holds the pure, unit-tested logic: features, model, filter, target selection and the dwell trigger.
- `Sources/FocusTracker` holds the app: camera, Vision, windows, hotkey, overlay, calibration and menu.
- The calibration is stored in `~/Library/Application Support/FocusTracker/calibration.json`.
- Logs use the subsystem `io.local.focustracker`: `log stream --predicate 'subsystem == "io.local.focustracker"'`.

## Development

```sh
./scripts/test.sh     # unit tests (Swift Testing)
swift build           # debug build of everything
```

`scripts/test.sh` wraps `swift test`. With only Command Line Tools installed, the Swift Testing macro plugin sits in a directory the compiler doesn't search by default, so the script passes its path explicitly.

## Limitations

- Main display only.
- Gaze accuracy depends heavily on lighting and camera placement. Glasses with strong reflections can reduce pupil tracking to head pose only.
- There's no eye-tracking hardware support on macOS, so the webcam is the only input.
