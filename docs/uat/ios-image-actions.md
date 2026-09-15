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
- ZephraEngine UpscaleTests: 13 tests passed.
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
- Prompt text scales at the largest accessibility size.
- Reuse closes the viewer, selects Canvas, and opens the populated composer.
- Offline metadata remains usable; offline upscale actions are disabled.
- Both upscale factors show the correct acknowledgment.
- Clip playback remains available; clip menus omit upscale actions.

Boundaries: simulator acknowledgments use the frozen client; encrypted request
routing and engine output are covered separately by tests. No physical-device or
live GPU upscale was performed. The available native UI driver did not reproduce
long-press or drag gestures reliably, so library long-press invocation and manual
scrolling at maximum accessibility size remain unverified; their shared menu and
prompt-sheet content were verified through the viewer's buttons.

Cleanup: simulator text size restored to Large, the test device shut down, and
Simulator quit. `simctl list devices booted` returned no booted devices.
