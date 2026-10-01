# FocusTracker

Look at a window, tap **left ⌃ (Control)**, and that window gets keyboard focus, so you can type into whatever you're looking at without reaching for the mouse.

FocusTracker is a macOS menu-bar app that estimates your gaze from a webcam using Apple's Vision framework. It outlines the window you're looking at, and focuses it when you tap the hotkey, or, in dwell mode, once you've kept looking at it for a moment.

> **Accuracy:** webcam gaze estimation is good to a few centimeters on screen. That's enough to tell tiled windows apart (halves, thirds, quadrants), but not small overlapping windows. It works out of the box with rough defaults, and gets more accurate as it learns from your clicks.

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
3. **Use it.** Tracking starts right away with a default model of how heads and eyes move. Every time you click, FocusTracker assumes you were looking at the pointer and learns from it, so accuracy improves over the first few dozen clicks. The menu shows the current typical error.
4. **Optional: Quick Calibrate.** For a faster start, click the 👁 menu-bar icon → **Quick Calibrate…**. Look at each dot as it appears, sitting as you normally do. A dot turns green while it's being sampled. The run takes about 25 seconds, and **Esc** cancels. Its samples join the ones from your clicks.

What is learned is how *your* eyes and head turn, not where you sit: your head position is measured on every frame. Leaving the desk and coming back, or moving your chair, doesn't require recalibrating.

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
| Accuracy ≈ N pt | Median distance between the estimated gaze and your recent clicks (or the calibration's validation dots). |
| Learn from Clicks | Uses your clicks as calibration samples (on by default). Only the click position and the face measurements at that moment are kept, locally. |
| Quick Calibrate… | Runs the optional dot calibration, for a fast start or after a big change in lighting or camera position. |
| Reset Learning | Forgets everything learned from clicks and calibration and goes back to the defaults. |
| Camera | Picks the camera to use. |
| Show Gaze Dot | Shows the estimated gaze point as a red dot: exactly the point used to pick the window. Useful for judging accuracy. |
| Use Mouse as Gaze | Debug mode: the mouse cursor stands in for your gaze, and the camera stays off. |
| Show Debug Window | Opens a camera preview and live head-pose, pupil, head-position and gaze-angle values. Use it to check the camera framing. |

## Tips for accuracy

- Put the camera at the top center of the screen, at roughly eye height, with your face well lit from the front.
- It's fine to turn your head a little toward the window you want. Head pose is the strongest signal, and learning picks up how your head and eyes move together.
- Check **Accuracy** in the menu. Under about 200 pt is good for a 2–3-way split on a large display. Clicks spread over the whole screen help more than many clicks in one spot.
- If the dot is mirrored or upside down before anything has been learned, run Quick Calibrate once. The defaults assume Vision's angle conventions and an unmirrored camera, and calibration overrides both.
- If tracking is still poor after a big change (new camera position, very different lighting), use **Reset Learning**, then Quick Calibrate.

## How it works

```
Camera (AVFoundation, 1280×720)
  → FaceFeatureExtractor   Vision face landmarks (76 points): head yaw/pitch/roll, pupil position
                           inside each eye, pupil midpoint and distance in the image, eye openness
  → BlinkDetector          drops frames taken mid-blink, when the pupil landmarks jump
  → FeatureMedianFilter    3-frame median: removes single-frame spikes
  → GazeGeometry           head position in mm from the pupil distance and position in the image
  → GazeModel              linear model: head pose + pupils + direction to the camera → gaze angles
  → GazeGeometry           gaze ray from the head position → point on the screen
  → GazeStabilizer         holds a fixation steady, jumps only when several points agree elsewhere
  → TargetSelector         topmost window under the gaze point, with a 250 ms dwell
  → DwellTrigger           dwell mode only: focus once the outline has held for the dwell time
  → HighlightOverlay       click-through outline on top of everything
HotkeyMonitor (left ⌃ tap) → WindowFocuser (Accessibility API: frontmost app + raise window)
ClickMonitor (left click)  → SelfCalibration (refits GazeModel from clicks and Quick Calibrate)
```

- **Why angles:** the model maps the face to gaze *angles*, and the geometry turns angles into a screen point using where the head is right now. What's learned about you therefore stays valid when you move. The old approach mapped the face straight to screen points, and broke as soon as you sat somewhere else.
- **Learning:** `GazeModel` is fitted by ridge regression toward a population default rather than toward zero, so with no data it *is* the default, and each sample pulls it toward you. `SelfCalibration` keeps at most 40 samples in each cell of a 4 × 3 screen grid, evicting the oldest, so clicks in one place can't dominate. After the first 20 samples, a click far from the estimated gaze (more than 3× the recent typical error, and at least 250 pt) is ignored, since you probably weren't looking at it.
- **Stability:** the red dot shows the same stabilized point the window targeting uses. A fixation moves by heavy smoothing only. A jump needs 3 consecutive points (about 100 ms) that agree with each other outside a radius of 3.5% of the screen diagonal.
- **Geometry assumptions:** the camera sits centered above the main display, in the screen's plane, with a 70° horizontal field of view (macOS doesn't report it), and an average 63 mm pupil distance. The screen's physical size comes from the display. Errors in these assumptions mostly become a consistent offset, which learning corrects.
- `Sources/GazeCore` holds the pure, unit-tested logic: features, blink detection, filters, geometry, model, self-calibration, target selection and the dwell trigger.
- `Sources/FocusTracker` holds the app: camera, Vision, windows, hotkey, clicks, overlay, calibration and menu.
- What has been learned is stored in `~/Library/Application Support/FocusTracker/gaze-profile.json`. A `calibration.json` from older versions is no longer used and can be deleted.
- Logs use the subsystem `io.local.focustracker`: `log stream --predicate 'subsystem == "io.local.focustracker"'`.

## Development

```sh
./scripts/test.sh     # unit tests (Swift Testing)
swift build           # debug build of everything
```

`scripts/test.sh` wraps `swift test`. With only Command Line Tools installed, the Swift Testing macro plugin sits in a directory the compiler doesn't search by default, so the script passes its path explicitly.

## Limitations

- Main display only, with the camera assumed to be centered above it.
- Gaze accuracy depends heavily on lighting and camera placement. Glasses with strong reflections can reduce pupil tracking to head pose only.
- There's no eye-tracking hardware support on macOS, so the webcam is the only input.
