# Product copy audit — 2026-09-11

Reviewed the product page against this branch's README and implementation.

| Claim | Evidence / disposition |
| --- | --- |
| Native macOS, Apple Silicon, MLX | `project.yml` declares macOS 15 and arm64; app uses SwiftUI and registered MLX backends. |
| Five model families | `ModelCatalog.swift`, `ModelCatalog+QwenImage21.swift`, `ModelCatalog+Flux2.swift` `ModelCatalog+Wan.swift` and `ModelCatalog+LTX2.swift` enumerate the named families and multiple quantized variants. Copy now says families. |
| Prompt and reference generation | README's reference workflow and each backend's reference handling support this; no claim of a general image editor. |
| Live previews, queue, searchable library | `PreviewThrottle`, `GenerationStore+Queue`, `LibraryQuery+Matching`, and the app's actual UI support these features. |
| 2× / 4× Real-ESRGAN | README and registered `ZephraUpscaleRealESRGAN` implementation; weights bundled locally. |
| Local generation, no app accounts/uploads/telemetry | README and source network scan: model transfer is in `ZephraSnapshot/Download`; no application telemetry integration. Claim explicitly scoped to the app. Downloads still need internet. |
| Offline after setup | Clarified that models need downloading and preparation first. No fixed memory, storage, or speed promises. |
| Portable PNG metadata | `LibraryAnnotation` embeds favorites, tags, album membership including names; generation record embeds prompt/seed. `AlbumManifest` retains empty albums/current names. Copy says album membership, not entire albums. |
| Availability | Version 0.1.0 (current build in `app/release.json`) is available as a Developer ID signed and Apple-notarized DMG. Public HTTPS download, checksum, stapled tickets, Gatekeeper, and mounted app/volume branding verified before linking. No invented pricing. |
| Artwork and screenshots | Actual app generation and completed-image window capture; original PNG metadata retained. Captured timings describe those runs only. See README for asset provenance. |
| Copyright | © 2026 James Brink, requested by the owner. |

Editorial headlines are positioning, not benchmark claims. Captions describe images
without presenting an invented quotation as an exact generation prompt.

## Getting started and compatibility update — 2026-09-08

- macOS 15 / Apple Silicon: `project.yml` and README requirements.
- Model disk figures: `ModelCatalog*.swift` download + built bytes; no catalog entry takes a second repository. Decimal GB, approximate; extra setup/library space called out.
- 16 GB guidance and streamed/resident peaks: README Models and memory and catalog measurement comments. Figures identify workload settings and are explicitly not minimum system RAM guarantees.
- First launch: README's installation/model workflow. Prepared mirror fallback is explained without promising a fixed download size.
- Release highlights: current LTX-2.5, MP4 library, and weight streaming implementation; version/build come from the same manifest as the download.
- Support email: `dev.urandom.io@gmail.com`, explicitly supplied by James in this task.
- Social card is a promotional imagegen composition using the approved icon and genuine app capture as references, not a new app screenshot. Original image and prompt retained in `design/website/social/`.

## Wan and audio update — 2026-09-11

- Rebased on `origin/main` at `be9b352` before updating copy.
- Wan 2.2 TI2V-5B: `ModelCatalog+Wan.swift`, text/reference inputs, 24 fps, up to 121 frames per segment, no audio. Built 10.1 GB; source + built 34.3 GB. Peak 15.1 GB, tiled 12.4 GB, streamed 9.7 GB at 832×480 / 49 frames.
- LTX-2.5 with sound: `ltx2DistilledAudio4bit`, `producesAudio: true`, MP4 stereo AAC at 48 kHz. Built 25.8 GB; source + built 96.8 GB. Measured 28.7 GB peak / 12.1 GB streamed at 768×512 / 49 frames.
- Video-only LTX figures updated for the spatial upsampler: 20.8 GB built / 91.5 GB with source; 23.4 GB peak / 10.0 GB streamed.
- Avoided the stale README statement that audio is only planned; catalog and backend implementation are authoritative here. Model-family count is five; audio is a variant of LTX, not a sixth family.
- Kept the original art and single download link. Release manifest is refreshed by the authorized notarized release publication, so the page does not advertise audio against the old download.

## User guide — September 11, 2026

Nine chapters plus `/guide/` cover first launch, models, prompting, starting images,
photo edits, text-to-video/audio, image-to-video/extension, library/export/upscale,
and settings/troubleshooting. Example prompts are original suggestions, not tested
output claims. No new generation benchmarks or inference runs were performed.

Source checks: `ModelCatalog*.swift` for actual variants/defaults; `ReferenceRole`,
`ReferenceAdoption` and `ReferenceImageWell` for labels and original-source reuse;
`ControlsRow`, `SeedControl`, `BatchCountControl`, `DurationControl`, `ChainPlan`,
`GenerationStore+Extend`, `GenerationStore+Chaining`, library menu and command
views, welcome chooser, model downloads, and performance/general settings.
The guide distinguishes the single-reference models from Qwen-Image 2.1's strip of
up to ten, Z-Image's Strength from direct conditioning, and LTX audio from silent
variants. It states Qwen-Image 2.1's research license, which is non-commercial and
the only such license in the catalog. It does not advertise upstream masks, prompt
enhancement, custom audio, or voice selection.

Primary upstream guidance consulted: Black Forest Labs' Building a Good Prompt
and Single-Reference Editing; Tongyi-MAI's Z-Image-Turbo model card; Qwen's
Qwen-Image 2.1 model card; LTX's
open-source Prompting Guide; Wan-Video/Wan2.2 `wan/utils/system_prompt.py`.
Direct source links appear in relevant chapters. App behavior takes precedence
over upstream tutorials for other variants or interfaces.

## Qwen-Image 2.1 update — 2026-09-22

- The catalog entry is `qwen-image-2.1-4bit`, from `Qwen/Qwen-Image-2.1`, and it
  replaces the model the earlier entries describe. Download 33.1 GB and built copy
  11.6 GB are the measured figures; the card reads 11.6 GB prepared and 44.7 GB with
  source files.
- Every memory and peak figure for this entry is an unmeasured estimate, so the page
  publishes none: the Qwen line is gone from the recorded-peaks note rather than
  carrying a stale or estimated number.
- License: the Qwen Research License permits research and evaluation only. That is
  stated on the getting-started card, in the models chapter, in `public/index.md`
  and in `public/llms.txt`, since every other model here is permissive.
- Controls and references: 40 steps by default (8-50), Guidance 1-8 default 1, and a
  negative prompt, which no other entry has; up to ten reference pictures read in
  order and conditioned on directly, so there is no Strength setting. The guide's
  reference role for it is Reference, not Start from.
- There is no adapter and no local merge step in the build any more.
