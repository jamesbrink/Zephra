# Reference pictures and upscaling

The long form of the matching section of `AGENTS.md`: the rules there, the reasoning and the history here. When the two disagree, `AGENTS.md` is wrong or this is stale; fix both.

## Starting from a picture

Every model Zephra ships can take at least one reference picture, and they take
it in four different ways. The difference is the whole of this section, because
the setting looks identical from the interface and means something else
underneath.

- **Conditioning on it.** FLUX.2 klein encodes the picture to tokens,
  concatenates them after the image being made with their own image index on the
  rotary embedding, and still walks the whole schedule from pure noise. See
  `Flux2ReferenceConditioning` and `Flux2Pipeline+Denoise`. The picture is
  something the model attends to, so there is no "how much of it to keep".
- **Conditioning on several, in order.** Qwen-Image 2.1 reads as many as ten.
  Each picture goes through the Qwen3-VL vision tower *and* through the
  autoencoder, and their latents become ordered prefix blocks the transformer
  attends over from a KV cache held across every step — which is why order is
  meaning here and why the strip can be dragged. Like klein it walks the whole
  schedule from noise, so it declares `referenceStrengthBounds` `1...1` and no
  slider is drawn. It is also the one family that reads a picture's alpha
  rather than being handed it over white, which it says with
  `ModelCapabilities.readsTransparentReferences`, and the prefix cache it holds
  is what `ModelDescriptor.referencePrefixBytes` charges: about half a megabyte
  a prefix token, doubled where guidance runs a second forward.
- **Starting from a noised copy of it.** Z-Image has no such conditioning path,
  but its autoencoder can encode and its schedule
  interpolates `x_t = (1 - sigma) * x0 + sigma * noise`, which is all SDEdit
  needs: encode the picture, noise it to the level some step expects, and resume
  from there. How far down to resume is a real choice, and it is
  `GenerationSettings.referenceStrength`.
- **Holding it as the first frame.** LTX-2.5 makes clips, and its autoencoder is
  causal in time, so one picture encodes to one latent frame that means what it
  would at the head of a longer clip. The picture is put there and the model is
  told, per token, that those tokens are less noisy than the ones it is making;
  the rest of the clip is generated around it. How strongly to hold it is a real
  choice too, and it is the same `referenceStrength` read the other way round —
  see "LTX-2.5" in `docs/model-weights.md` for the whole of it, and `LTX2RequestMapper` for the one
  place the inversion happens.

`referenceStrength` is a plain `Double`, not an optional, because every
generation has one whether or not its model reads it, and 1 is the value that
changes nothing. `ModelCapabilities.referenceStrengthBounds` says whether it
applies at all: a degenerate `1...1` means it does not, the way `guidanceBounds`
of `0...0` means guidance does not, and `clamp` pins it there. klein,
Qwen-Image 2.1 and Wan declare `1...1`; Z-Image declares `0.1...0.9` with a
default of `0.6`; LTX-2.5 declares `0.0...0.9` with a default of `0`, because 0
there means the first frame is held exactly rather than "the picture is returned
unchanged". So the interface can decide whether to draw a slider by reading the
range, without knowing which family it is looking at, and "lower keeps more of
the picture" is true wherever one is drawn.

**How many** is `ModelCapabilities.referenceImageCount`, `1...1` for every entry
but Qwen-Image 2.1's `1...10`, with `acceptsSeveralReferences` the computed
answer the well branches on. Above every capability sit `ReferenceLimits`' two
hard caps, which no descriptor may exceed: `maximumPictures` is 10, because the
numbered PNG keywords stop at `zephra:reference.10`, and `maximumTotalBytes` is
24 MiB across the **whole strip** rather than per picture, since ten
1024-pixel PNGs are what a link and a record have to carry together.
`ModelCapabilities+Clamp.constrainReferences` is where all of it lands, in this
order: nothing at all for a model that reads none, then every picture whose
bytes were stripped for the wire dropped, then
`prefix(min(referenceImageCount.upperBound, ReferenceLimits.maximumPictures))`,
then `ReferenceLimits.withinBudget`, which drops from the **end** so the picture
chosen first is the one that survives.

`GenerationSettings.referenceImages` is the stored truth and
`referenceImage`/`referenceOrigin` are computed aliases over its first element,
permanently rather than as a migration: five backends, the bench and some thirty
readers were written when there was one picture, and the aliases are what kept
them true. Setting `referenceImage` replaces the list with one picture; setting
`referenceOrigin` on an empty list does nothing, because an origin with no
picture would be a request claiming provenance it has not got.

**The record numbers its chunks.** The first picture stays in
`zephra:reference`, unsuffixed — there is deliberately no `.1` — and the rest go
in `zephra:reference.2` through `.10`. `GenerationRecord.referenceByteCounts`
and `referenceOrigins` are written **only when there is more than one picture**,
so a one-picture edit's PNG is byte for byte what it always was; a reader
without them falls back to `[referenceBytes]` and `[referenceOrigin]`. Reading
stops at the first chunk that is missing or whose bytes are not the length the
record claims, so a file whose fourth chunk went bad is an edit of three
pictures rather than of none.

**One ticket covers the whole strip.** `GenerationStore.claimReference()`
numbers a choice when it is made rather than when its bytes arrive, and a drop
of five files is one choice landing as one `adoptReferences` — five tickets
would land only the last. `referenceRoom` is what is left, and D7's rule is one
line in `GenerationStore.useAsReference`: **where there is room it appends;
where there is not it replaces the whole strip.** "Use this as the reference"
with ten already in can only honestly mean starting afresh with the one chosen,
and on a model that reads one it is always the second branch. A door handed
exactly one picture still goes through the single-picture door, so the rule
stays written once. The phone's `PromptDraft+ReferenceStrip` implements the same
rule, and `UseAsReferenceLabel` reads the same answer the press does, so it says
"Add to References" where there is room and "Use as Reference" where there is
not.

For the models that start from a noised copy:

- Strength reads as "how much of the picture to throw away". 1 discards it
  entirely and is the ordinary text-to-image path; 0 would return it unchanged.
  Neither end is offered, which is why the bounds stop at 0.1 and 0.9.
- **Strength buys a share of the steps, not a noise level.** `steps * strength`
  of them run, truncated and never fewer than one, so every strength the slider
  offers keeps some of the picture, and the loop enters that far from the end,
  starting from the encoded picture mixed with that step's share of the run's
  own seeded noise. So 0.6 of Z-Image's nine steps enters at 4 and runs 5, and
  0.9 of those nine is 8.1, which runs 8 from an entry of 1. Reading strength as
  a share is diffusers' `get_timesteps` mapping, and following it rather than
  entering at the first sigma at or below the strength is load-bearing: **a
  distilled ladder is not evenly spaced.** Z-Image's nine sigmas crowd towards
  the end, so the noise-level reading sends the bottom of the slider to one of
  the last few and hands the picture back all but untouched — which is exactly
  what it did on a four-step ladder, where sigmas of 1.0, 0.767, 0.456 and 0.02
  sent every strength from 0.1 to 0.4 to that 0.02. The truncation is a
  deliberate departure from `get_timesteps`, which takes the ceiling of the
  share: the ceiling of 0.9 of nine steps is nine, an entry of 0, where the mix
  is pure noise and the picture is discarded at the top of the slider. The
  product is nudged up by a hair before it is truncated (`1e-7` on the `Float`
  strength in `ReferenceLatents`), because ten `Float` steps of 0.7 land at
  6.9999999; the slider's 0.05 granularity is what makes the nudge safe.
- Progress still counts against the full step count, so a queue card drawing one
  segment per step shows the skipped ones as finished rather than showing a
  shorter run.
- `ZImage.ReferenceLatents` is the entry-point arithmetic, pure and pinned by
  its own suite, and it is the only implementation left — there were two while a
  second family read a picture this way. It lives inside vendored code that is
  re-synced against upstream, which is why the rule above is written here and
  not only there: a second copy would have to be kept in step by hand.
- `GenerationRecord.referenceStrength` records what ran, beside
  `referenceBytes`. Nil when there was no picture; 1 when the model conditioned
  on it directly, which is how a klein edit says it had no distance to travel.
- `GenerationSettings.referenceOrigin`, recorded as `GenerationRecord`'s field
  of the same name, is the library **file name** the picture came out of — nil
  for a file chooser pick or a drop, and a name rather than a path for the
  reason the record lives inside the PNG. `useAsReference` and `adoptReference`
  take it beside the picture, clearing the picture clears it, and `clamp` drops
  it wherever it drops the picture; `LibraryIndex.item(named:)` is the lookup
  back to the file, Recently Deleted excluded. `ImageFacts` shows it beside
  `referenceStrength` and the raw `referenceStrengthValue`, since LTX-2.5's
  scale runs the other way and its 0 is a phrase rather than a number.

Animating a picture is the third thing a picture can be, and it is one call:
`GenerationStore.animate(origin:read:)` picks whichever catalog entry makes
clips *and* reads a picture (`ModelCatalog.animator(among:)` — a capability
question, so the engine still names no family), chooses it without loading it,
sets the clip's length to that model's default, and reads the picture through
the same numbered choice every other door into the well uses. The prompt is
kept: the person is animating this picture with their prompt, which is what
tells Animate apart from a variation. `canAnimate` is `acceptsWork` and this
build having such a model, which is what the interface greys the button by,
disabled rather than hidden the same way `supportsReferenceImage` greys Use
as Reference. The size follows the picture in `useAsReference` rather than in
`animate` — on a model that makes clips a picture landing in the well moves
`settings.size` to `ModelCapabilities.size(matchingAspectOf:budget:)`: the
picture's own shape, at the pixel count of the size in force, rounded to the
model's grid — so a drop, the picker, Use as Reference and Animate all agree.
The shape rather than the nearest preset, because a clip is the picture
moving and a 4:3 photograph at a 3:2 preset is cropped before a frame is
made; the budget rather than a fixed size, so a person who chose a small
frame keeps a small frame. Animate is the one exception on the budget: when
it switches from a picture model, the clip model's own default is the budget,
since 1024 x 1024 carried over from Z-Image would make the clip two and a half
times the default's pixels. A picture model leaves its size alone; its
picture is a reference for the image asked for, not the image.

Extending a clip is the fourth thing a clip can be the start of, and it is one
call, `GenerationStore.extend(_:)`, mirroring Animate: the clip's own model is
chosen without loading it when it can hold a clip's end
(`ModelCatalog.continuer(for:)`, else the animator), the last
`defaultContinuationFrames` frames are read off the main actor through the
`ClipEditing` the root injected (`MP4Stitcher` in `ZephraMedia`; the engine
knows only the protocol in `ZephraCore`), and the capsule is set up with the
clip's own prompt and size, the model's default length and strength, and the
tail: its last frame in the well, under the `ReferenceRole.continues` caption,
and the whole tail as `GenerationSettings.continuation`. The frames are bytes,
not a path, for the reason the reference picture is; the published image drops
them (`ClipContinuation.withoutPixels`) so history never holds a tail. Putting
any other picture in the well drops the continuation, because the picture in
the well *is* the continuation's last frame.

How a family holds the tail is `ModelCapabilities.continuationFrames`, the
degenerate-range convention again: `0...0` cannot; Wan declares `1...1` and
holds the last frame exactly as it holds a first frame, since its base model
was trained on one held frame; LTX-2.5 declares `1...25` on its ladder of
eight and holds the `1 + 8k` frames as `k + 1` clean latent frames at the
head, the reference's multi-frame condition at latent index 0 — the per-token
noise level covers every held frame, the keyframe embedding stays on the first
latent frame alone (`transformer_conditioned_span` pins both), and both stages
of a two-stage run encode the tail at their own size. `clamp` drops the
continuation on a model without it and trims the frame list down the ladder,
newest frames kept. `LTX2RequestMapper` holds the tail over the well's
picture; `WanRequestMapper` holds its last frame.

What one held frame costs, on Wan: a still frame says where the clip is and
nothing about where it was going, so each pass re-establishes the model's own
motion and a chained clip reads as several clips cut together rather than one
long one. That is the conditioning the reference gives this family, not a
defect in the hold — the hold itself is exact, and a held run comes back as the
source's own frames at the autoencoder's round-trip error. Holding a run
instead was measured on 2026-09-11 and is worse: the frame after the run jumps
two to six times the clip's own frame-to-frame change, since the base model was
trained with exactly one clean latent frame. `ROADMAP.md` carries the numbers
and the LoRA that would train the rest. A clip that has to stay continuous
across a seam belongs on LTX-2.5, which holds 17 frames and was trained to.

The join is the run's: after the backend hands the segment back,
`GenerationStore+Stitching` finds the source by its library name (the images
folder, then Recently Deleted, since a clip deleted while its continuation
waited is still there), drops the segment's first `contextFrames` frames — the
held ones, which the model re-draws — and stitches the two through the same
`ClipEditing`, one re-encode. The published clip's poster is the source's,
stripped of its chunks so it takes a record of its own; `frameCount` is the
whole clip; the record says `continuedFrom` and `contextFrames`, and no
reference, since the frame in the well was the clip's own. A source gone from
both folders fails the run and writes nothing; the segment alone is never kept.
`ExtendTests`, `ContinuationCapabilitiesTests`, `ClipTailTests` and
`MP4StitcherTests` pin it.

Each backend package decodes the bytes to a `CGImage` in its own
`ReferenceImageDecoding` — a small file duplicated per package, because no backend
package may import another. Backends decode; the kits are handed decoded images
and never touch the filesystem.

**A transparent reference is matted over white, except where a model reads
alpha.** Every bitmap a reference is drawn into — `Flux2PixelBuffer`,
`CoveringPicture`, and `UpscalePixelBuffer` for a picture with no alpha channel
— is cleared to white before the draw. It used to be black, and that was never a
decision: a fresh `CGContext` buffer is zeroed, `noneSkipLast` reads the zeroes
as black, and a transparent picture drawn into it lost its clear regions to it.
Transparent pictures were not producible inside Zephra before there was a model
that makes them, so the default had to be chosen rather than inherited, and
white is what a person expects and what Qwen-Image 2.1's own pipeline prescribes
for its reference tower. Each site says so in a comment beside the fill.

`QwenImage21ReferencePicture` is the exception, and it is the reason the rule
had to be stated rather than assumed: it hands the autoencoder all four
channels and flattens over white only for the vision tower, which is what
`readsTransparentReferences: true` promises. Neither `ReferenceImageEncoder`
mattes either — both ends re-encode a thumbnail at 1024 pixels an edge and
alpha survives into the well — so the matte is the pipeline's decision and is
made as late as it can be.

**The interface says when a matte will happen.** `ReferenceMatteNote` reads the
pictures' own PNG headers off the main actor, on the bytes already in hand
rather than from a file, and answers "Read over white by \(model)." when the
model does not declare `readsTransparentReferences` and at least one picture
carries alpha. The model is **named**, because the answer moves with it: the
same strip is matted by one model and not by another. `ReferenceNotes` is the
modifier that stacks that line under the well with the store's own refusal line
and adds nothing to the layout when there is nothing to say.


## Upscaling

Upscale 2x / 4x is Real-ESRGAN's compact network (`realesr-general-x4v3`,
SRVGGNetCompact: 34 convolutions at 64 channels with per-channel PReLU, a pixel
shuffle, and a nearest-neighbour residual), 1.2M parameters, BSD-3-Clause. It is
the first non-diffusion step in the app, and the seam it sits behind is the one a
later post-process should copy:

- `ImageUpscaler` in `ZephraCore/Upscale/` is the whole protocol: PNG bytes in,
  PNG bytes out at `UpscaleRequest.factor` times each edge, progress by tile,
  cancellation between tiles. It is deliberately not `ImageGenerationBackend`:
  that protocol is about one model family resident at a time, and an upscaler
  needs no model loaded and holds five megabytes.
- `InferenceActor` owns the one upscaler, built lazily from the injected
  `UpscalerFactory` and kept resident across model switches; it runs on the same
  serial queue as a generation, so two Metal jobs never overlap. The store's
  `GenerationStore+Upscale.swift` drives it through `EngineState.upscaling`,
  restores whatever state it started from, and refuses to start unless the engine
  is idle, ready, or failed; Generate greys out for the seconds it runs.
- The result is a new PNG in the library root named `<parent stem>-x<factor>.png`,
  carrying the parent's record with the new size, `upscaledFrom` and
  `upscaleFactor` set, `batchID` cleared, and the parent's reference chunk copied
  verbatim. An imported parent gets a minimal record so the result is indexed.
  Nothing rewrites the parent. A grid cell and a sidebar square wear an
  `UpscaleBadge` (`ZephraStyle`) in the top-left corner, because an upscale looks
  exactly like its parent at thumbnail size.
- The weights are bundled as a package resource, 2.4 MB of float16 safetensors
  converted once by `Packages/ZephraUpscaleRealESRGAN/Tools/convert_weights.py`
  from the v0.2.5.0 release asset; `PROVENANCE.md` there records the checksum.
  2x is the 4x pass followed by an exact 2x2 box mean; the network is 4x only.
  The picture runs through `TiledDecode` in 512-pixel input tiles at scale 4;
  a 1024 input measured 2466 MB peak and 3.75 s at 4x on an M4 Max, and 2x
  costs the same peak because the 4x join sets it. The port is written from
  `srvgg_arch.py` and never from `xocialize/realesrgan-mlx`, which has no
  license.
- **Transparency goes through, in two lanes.** A picture with an alpha channel
  is split by `UpscalePixelBuffer.pixels` into its straight colour — the
  premultiplication a bitmap context imposes divided back out, a wholly clear
  pixel taking white — and its alpha plane. The colour runs through the network
  as itself; the alpha runs through as a grey triplet, the same plane in all
  three channels, and the mean of the three outputs is the new alpha. The
  network never learned a fourth channel, but it did learn to enlarge a grey
  picture, and an alpha plane is one: its edges are the picture's edges and want
  the same treatment. The two are recombined as straight RGBA and written as an
  RGBA PNG. That is twice the tiles, and the progress counts both lanes. A
  picture with no alpha channel runs one lane and comes back exactly as it
  always did.

Everything the upscaler leaves out on purpose is listed in `ROADMAP.md`.
