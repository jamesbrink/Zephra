# iOS image actions validation — 2026-09-15

## Delivered

- Copy Prompt and Reuse Settings in shared image menus.
- Tappable prompt heading and View Prompt sheet, with selectable complete text and copying.
- Full-width collapsed canvas image at larger text sizes; tap opens the shared viewer.
- Upscale 2× and 4× on the source Mac, with acknowledgment/refusal and no automatic retry.

## Automated checks

- iOS Debug build: passed.
- iOS: 205 tests in 43 suites passed.
- ZephraLink: 275 tests in 51 suites passed.
- ZephraKit: all 801 tests in 150 suites passed, including 13 upscale tests.
- Layer lint and whitespace checks: passed.
- Independent sub-agent review: findings addressed; final review had no remaining findings.

New regressions cover settings restoration, preserving choices against the first
host snapshot, clearing unrelated reference data, missing provenance, video
settings, encrypted owner-specific upscale requests with duplicate filenames,
2×/4× factors, refusal/offline behavior, invalid factors/video rejection, and a
lost acknowledgment producing exactly one upscale request.

## Simulator UAT

iPhone 17 Pro, iOS 26.5; frozen local fixtures, including an offline second Mac.

Verified interactively:

- Canvas image uses available width at XXXL text size and opens full screen.
- Viewer opens/closes, double-tap zooms, and a tap hides/restores controls.
- Prompt heading and View Prompt menu action open the reading sheet.
- A 690-character, three-paragraph prompt displays through its final sentence.
- Copy from the prompt sheet exactly matches all 690 characters and newlines.
- Prompt text scales at the largest accessibility size; drag scrolling reaches the final sentence.
- Reuse closes the viewer, selects Canvas, and opens the populated composer.
- Long-pressing a library image opens its actions; Reuse Settings works from that menu.
- Offline metadata remains usable; offline upscale actions are disabled.
- Both upscale factors show the correct acknowledgment.
- Clip playback remains available; clip menus omit upscale actions.

## Live upscale UAT

A separately launched Debug Mac app used an isolated preferences, model, companion,
and image directory under `/tmp/zephra-ios-uat/live-host`. A real encrypted LAN
pairing connected the simulator to this host. No diffusion model was loaded.
The bundled Real-ESRGAN upscaler ran on Metal against a disposable 128×128 PNG.

Both actions were invoked by long-pressing the original image on iOS. Each showed
its acknowledgment, completed on the Mac, and appeared in the phone's library.
PNG dimensions and embedded generation provenance were checked:

| Action | Output | Provenance |
| --- | --- | --- |
| 2× | 256×256 | `upscaleFactor: 2`, original source filename |
| 4× | 512×512 | `upscaleFactor: 4`, original source filename |

The 4× result was opened full screen on iOS and visually inspected. Retained local
evidence includes `/tmp/zephra-ios-uat/live-upscale-x4.png`,
`full-prompt.png`, `canvas-large-text.png`, and the input/output PNGs in the isolated
host's `Images` directory. No physical iPhone was tested.

## Cleanup

Simulator text size was restored to Large. The test-only phone pairing was revoked,
the isolated Mac's companion connection was disabled, and that app was quit. The
test simulator was shut down; `simctl list devices booted` returned no booted
devices, and neither the UAT Mac app nor Simulator remained running.
