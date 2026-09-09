# Product copy audit — 2026-09-08

Reviewed the product page against this branch's README and implementation.

| Claim | Evidence / disposition |
| --- | --- |
| Native macOS, Apple Silicon, MLX | `project.yml` declares macOS 15 and arm64; app uses SwiftUI and registered MLX backends. |
| Four model families | `ModelCatalog.swift`, `ModelCatalog+QwenImage.swift`, `ModelCatalog+Flux2.swift` and `ModelCatalog+LTX2.swift` enumerate the named families and multiple quantized variants. Copy now says families. |
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
- Model disk figures: `ModelCatalog*.swift` download + built bytes; Qwen includes its Lightning adapter. Decimal GB, approximate; extra setup/library space called out.
- 16 GB guidance and streamed/resident peaks: README Models and memory and catalog measurement comments. Figures identify workload settings and are explicitly not minimum system RAM guarantees.
- First launch: README's installation/model workflow. Prepared mirror fallback is explained without promising a fixed download size.
- Release highlights: current LTX-2.5, MP4 library, and weight streaming implementation; version/build come from the same manifest as the download.
- Support email: `dev.urandom.io@gmail.com`, explicitly supplied by James in this task.
- Social card is a promotional imagegen composition using the approved icon and genuine app capture as references, not a new app screenshot. Original image and prompt retained in `design/website/social/`.
