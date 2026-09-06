# LTX-2.5 on Zephra: a first look

Research note, 2026-09-06. High level only; nothing here has been run. The point is to
record what the model is, what it would cost on Apple Silicon, and where it does and does
not fit the backend seam, so the decision to pursue it can be made without redoing the
reading.

## The model

Released 2026-08-11 by LTX, the world-model company spun out of Lightricks. A 22-billion
parameter joint audio and video DiT, conditioned on a Gemma 4 12B text encoder that LTX
fine-tuned and shipped with its projection bundled in (Google's stock Gemma 4 is not a
substitute), decoded by a 128-channel video VAE, with an audio VAE and BigVGAN vocoder for
48 kHz stereo audio, two latent upscalers (2x spatial, 2x temporal) for the second stage,
and a 2 MB duration head that predicts clip length from the prompt.

Constraints the interface would have to express:

- Frames are `8n + 1` at 24 fps: 9, 17, ..., 121 (5 s), 193 (8 s).
- Width and height divisible by 32. Stage 1 at 544x960, stage 2 at 1088x1920, 4K via the
  spatial upscaler.
- The distilled transformer runs a fixed eight-sigma schedule, eight steps in stage 1 and
  four in stage 2, with no guidance and no negative prompt. That is the shape of klein and
  Qwen-Lightning already in the catalog, so `ModelCapabilities` expresses it today.
- Text-to-video, image-to-video (first-frame conditioning, which is what
  `GenerationSettings.referenceImage` would map to), video-to-video, audio-to-video.
- LTX-2.5 over 2.3: DFR (diffusion fidelity rendering, dynamic compute per scene), native
  multishot, the duration head, and one file per component.

## Checkpoints

| Repository or file | Role | bf16 size | Notes |
|---|---|---|---|
| `Lightricks/LTX-2.5` distilled transformer | 22B DiT, 8 steps | ~44 GB | the variant to ship |
| `Lightricks/LTX-2.5` dev transformer | 22B DiT, CFG, variable steps | ~44 GB | quality path, twice the compute |
| `gemma4-12b-with-proj-ltx-2.5` | text encoder | ~24.4 GB | the memory problem |
| video VAE (conv) / DiffVAE decoder | decode | 726 MB / 417 MB | conv is fast, Diff is better |
| audio VAE + vocoder | audio | ~180 MB | |
| spatial x2 + temporal x2 upscalers | stage 2 | 498 + 131 MB | needed above 540p |
| duration head, 450-step LoRA | optional | 2 MB / small | |
| `nvfp4`, `comfy-int8-convrot` | quantized | | CUDA and ComfyUI formats, not MLX-readable |
| `mlx-community/ltx-2.5-mlx` | MLX split layout | ~110 GB | bf16 per component, consumed by both MLX ports |

No published 4-bit MLX pack exists. Zephra would do what it does for Qwen-Image: download
the bf16 release, about 71 GB for one transformer plus the encoder, and pack it locally
through `ZephraQuantization`. A 4-bit build would be roughly 12 GB of DiT, 7 GB of
encoder and 2 GB of VAE, audio and upscalers, about 21 GB on disk. Both figures are
Qwen-Image's, so the download and build machinery already handles this scale.

## Memory on Apple Silicon

Measured by others; nothing here is ours yet.

| Configuration | DiT resident | Text encoder | Peak | Time | Source |
|---|---|---|---|---|---|
| int4, 512x288, 121 f (5 s) | ~12 GB | evicted after encode | 15.4 GB | 64 s | ltx-2-mlx-swift |
| int4, 5 s clip | ~12 GB | | 16.3 GB | 29.7 s | PocketAIHub, M5 Max |
| int8, 5 s clip | ~21 GB | | 24.0 GB | 33.3 s | PocketAIHub, M5 Max |
| int8, 704x512, 161 f | ~21 GB | | 37.5 GB | 188 s | ltx-2-mlx-swift |
| bf16, 1024x576, 5 s | ~44 GB | co-resident | 43.1 GB | 143 s | LTX Desktop, M5 Max |
| bf16, 704x512, 481 f | ~44 GB | | 72.7 GB | 960 s | ltx-2-mlx-swift |
| Gemma 4 12B alone | | bf16 24.4 / 8-bit ~12.5 / 4-bit ~7 GB | | | arithmetic |

Against Zephra's budgets (`MemoryBudget`, Metal's recommended working set):

- 16 GB (bender, 12.1 GB working set): does not fit resident even at 4-bit. The only
  path is `LayerWeightStream` over the 22B blocks, as Qwen-Image streams, with a 4-bit
  encoder freed before the DiT loads. Expect Qwen-class step times or worse.
- 32 GB: 4-bit DiT, encoder quantized and evicted, short clips at about 540p.
- 48 GB (halcyon): 8-bit distilled comfortably; bf16 only streamed.
- 64 GB and up: bf16 resident.

## Where it fits the seam

Fits as the seam stands:

- A backend package `ZephraBackendLTX2` and a kit `LTX2Kit`, one `BackendID`, catalog
  entries with `builtBytes` and `streamedPeakBytes`, registered in `ZephraApp.swift`. The
  `build` step packs through `ZephraQuantization` with a per-tensor plan, as klein does.
- Streaming: the DiT is a stack of identical blocks, so `LayerWeightStream` applies
  directly. This is what gets it onto 16 and 32 GB Macs at all.
- Distilled, no guidance, no negative prompt: expressed by `ModelCapabilities` today.
- Live preview: `onPreview` per step exists; a video preview is one pooled frame.
- Reference image: image-to-video is first-frame conditioning.

Does not fit, in order of pain:

1. Output type. `ImageGenerationBackend` returns PNG bytes, and the library, history,
   export, copy and inspector all assume one PNG with two text chunks. Video is an MP4
   with an AAC track. Either a parallel `VideoGenerationBackend` and a `LibraryItem` kind
   that keeps the record in an MP4 metadata atom or a sidecar, or a generalised
   `GeneratedMedia`. This is the design decision; the model port is the smaller job.
2. Text encoder lifecycle. 24 GB bf16 is more than klein's whole footprint. The backend
   must encode, then free the encoder before the DiT is touched, and either reload it per
   prompt or keep a 4-bit copy. `InferenceActor` holds one backend, so this stays inside
   the backend, but it changes what `residentBytes` means for the entry.
3. Two stages. Stage 1 at 544x960, latent upscale, stage 2 refine, then two VAE decodes.
   Progress and cancel points multiply; the step bar wants `BuildTally`-style weighting.
4. New settings. Duration or frames, fps, audio on or off, resolution tiers.
   `ModelCapabilities` needs bounds for time as well as size.
5. Licensing. The weights are under the LTX-2.x Community License: free under $10M
   annual revenue, a paid agreement above, redistribution must propagate the terms, and it
   carries a non-compete clause (section A.20) and asymmetric indemnity. Gemma 4 adds
   Google's Gemma Terms of Use. Both belong in `THIRD_PARTY_NOTICES.md`, and the
   non-compete wants a read before Zephra ships it commercially. It also constrains a
   CDN mirror of packed variants (see `make mirror`): a redistributed derivative has to
   carry the licence.

Porting sources, with attribution the way `Flux2Kit` was done: `xocialize/ltx-2-mlx-swift`
(Apache-2.0, Swift; Gemma through `mlx-swift-lm` main for all-hidden-states access, not in
a tagged release yet) and `dgrauet/ltx-2-mlx` (MIT, Python). The Lightricks reference code
pins parity. Nothing without a licence.

## Recommendation

Feasible. The memory and build story is already solved by the Qwen-Image work; the real
cost is the video output seam through the library and the interface. First step, before
any interface work: a `ROADMAP.md` entry and a spike running the distilled 4-bit DiT
streamed through `LayerWeightStream` in `ZephraBench` on halcyon, for a real step time.

## Sources

- https://huggingface.co/Lightricks/LTX-2.5
- https://huggingface.co/Lightricks/LTX-2.5/blob/main/README.md
- https://github.com/Lightricks/LTX-2
- https://github.com/Lightricks/LTX-2/blob/main/LICENSE.md
- https://huggingface.co/mlx-community/ltx-2.5-mlx
- https://github.com/dgrauet/ltx-2-mlx
- https://github.com/xocialize/ltx-2-mlx-swift
- https://x.com/trevorwood222/status/2088624880283779209 (PocketAIHub M5 Max timings)
- https://note.com/tamilab/n/n9d4b2160b588 (LTX Desktop on an M5 Max)
- https://rapidmlx.com/docs/models/families/video
- https://comfyui-wiki.com/en/news/2026-08-11-ltx-2-5-open-weights-release
- https://wavespeed.ai/blog/posts/blog-ltx-2-license-commercial-use/

## What shipped (2026-09-06, `feat/ltx2`)

- The video-only distilled transformer at four bits, packed from the ungated
  `mlx-community/ltx-2.5-mlx` pack: both Lightricks repositories turned out to be
  gated (`gated: auto`, 401 without a token), which Zephra's no-token downloader
  cannot pass. 69 GB down, 19.3 GB built in 82 s.
- Measured on an M4 Max: 768 x 512 x 49 frames in 63.4 s (7.0 s a step), 17.5 GB
  live, 21.8 GB peak; 512 x 288 x 9 frames in 10.4 s (0.90 s a step). The
  estimates in the table above were pessimistic on speed and about right on memory.
- Two facts the first look missed: every attention module is gated per head
  (`to_gate_logits`), and the pack's Gemma 4 has eight full-attention layers that
  share their key and value projection (`attention_k_eq_v`). Both are in the port.
- Left for later, in `ROADMAP.md`: the audio stream (the seam is written), image-to-video,
  two-stage and DFR refinement, temporal decode chunking.
