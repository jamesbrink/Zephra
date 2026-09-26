# iOS viewer save and prompt regression checks

2026-09-26, iPhone 17e Simulator, iOS 26.5, Debug viewer fixtures.

- Passed 247 hosted iOS tests, including current-page, version and host URL identity guards.
- Passed 297 link tests, followed by the added encrypted 65 MiB file transfer test.
  The latter verifies the exact received bytes and release of the client memory reservation.
- Passed layer lint, whitespace validation and the final iOS build.
- Inspected normal and maximum accessibility text sizes. Short prompts fit their text;
  long/enlarged prompts scroll vertically without ellipsis. The explicit full-prompt
  action opened a readable, selectable prompt sheet at maximum text size.
- Granted add-only Photos permission in Simulator and pressed Save in the viewer.
  Photos completed the import and the success alert appeared.
- Independent subagent reviewed the final changes with no outstanding findings.

Screenshots: [normal](ios-viewer-save/normal-text.png),
[maximum text](ios-viewer-save/large-text.png),
[full prompt](ios-viewer-save/full-prompt.png),
[Photos success](ios-viewer-save/saved.png).

The media fixtures are cached numbered pictures. A delayed live-network swipe/save
sequence and a physical-device upscale were not reproduced in this session. The
transfer regression runs through the encrypted in-process host/client path, while
stale URL rejection is covered by automated identity tests and review of cancellation,
paging disable state, entry capture and save-owned cache lease lifetime.
