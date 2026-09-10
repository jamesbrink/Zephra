# Model weights

The long form of the matching section of `AGENTS.md`: the rules there, the reasoning and the history here. When the two disagree, `AGENTS.md` is wrong or this is stale; fix both.

## Model weights

Every measured figure — download, built and resident sizes, peaks, step times,
what streams at what rate, and which of those is owed a rerun — is in
`BENCHMARKS.md`, beside the Mac it was taken on. This section is the rules
those figures decide and the things about each family that are load-bearing and
easy to undo.

Weights live in the folder Settings > Models names, which is
`~/Library/Application Support/Zephra/Models` until the user changes it:
`Downloads/<org>--<repo>` for a release, `<descriptor id>` for a variant packed
here. `make prefetch` writes exactly what the app would have written, so it
seeds a first launch; and a prefetch that was interrupted is finished by the
app, which then removes the `.incomplete` partials `hf` left under the folder's
`.cache/huggingface/download`, since a partial nothing will finish would
otherwise hold the folder incomplete for good. The hub cache is still read if it
holds a release — a Mac that ran `hf download`, or an older Zephra — but nothing
is written there any more, and neither `HF_HOME` nor `HF_HUB_CACHE` decides
where a download goes.

Every repository the catalog names is public and ungated, so no download needs a
Hugging Face token — and Zephra sends none: `ModelDownloader` never sets an
`Authorization` header, whatever is in `HF_TOKEN` or in the token files the `hf`
tool reads, which is one whole class of "authentication required" for a public
model that cannot happen. There is no metered-network refusal either: the size
is on the screen before the download starts, so whether to spend it on a hotspot
is the user's call. A download that breaks is tried again by `DownloadRetry` in
`ZephraCore`, five times with a doubling pause, and each file resumes from its
`.incomplete` bytes, so a retry and a later Try Again both continue rather than
start over. Only a missing repository, a missing file, or a 4xx that is not a
timeout or a rate limit stops the retrying early.

Settings > Models lists every directory the catalog's models have on this Mac —
the app's own folder first, then either hub layout — with where it is, its size,
and a Delete that permanently removes its files after confirmation.
`ModelStorage` in `ZephraSnapshot` is the listing and the measuring, and each
`ModelStorageItem` says where it was found (`origin`: the app's folder or the
hub cache), since only a partial in the app's own folder resumes when its model
is chosen; `ModelInventory` in `ZephraEngine` is what the tab observes. A
release two variants pack from is one row naming both, a download stopped
part-way is a row saying so, an adapter is a row of its own named for the model
it serves ("Qwen-Image 2512 adapter"), and a directory the loaded model is using
cannot be deleted from under it. Changing the folder offers Move Models, Keep in
Place, or Cancel. Keep retains previous roots as read-only fallbacks. Move
unloads the model, copies catalog-owned downloads and builds into staging,
verifies bytes, then publishes them before removing originals. A collision
refuses the move without overwriting either copy. Cleanup failure keeps the new
location and reports leftover originals. Move Models Here chooses one previous
root explicitly. Neither migration path touches the image library or the hub
cache. Preparation is stopped by a folder change and resumes only when requested
from the canvas; generation, queued work, upscaling, and deletion cannot race
migration.

### Z-Image-Turbo: `z-image-turbo-8bit`, `z-image-turbo-4bit`

The 8-bit entry is `mzbac/Z-Image-Turbo-8bit`, 13.3 GB excluding `assets/`,
and the one model in the catalog loaded exactly as downloaded; its 1024-pixel
decode peaks near 23.5 GB, so 32 GB of RAM is its practical floor. Always pass
the model explicitly when calling into the vendored pipeline — its own default
is the 32.9 GB bf16 repo, which Zephra reads only as a build source and never
loads.

The 4-bit entry is packed on the user's own Mac from that bf16 release
(`Tongyi-MAI/Z-Image-Turbo`), because no repository publishes four-bit
Z-Image-Turbo in the manifest format the vendored loader reads. The app does it
on first load, the way klein does; `make quantize` is the same build by hand.
Group size is 64, measured against 32. A 16 GB Mac is offered this variant: 512
fits outright, and 768 and 1024 fit once the decode is tiled, which Automatic
does. Four bits is not faster than eight, since MLX's quantized matmul costs the
same at these shapes whichever width it packs.

Three things about the Z-Image plan are load-bearing and easy to break:

- The set of packed tensors must match the reference eight-bit export exactly.
  The loader decides what is quantized by looking for a `.scales` key, so
  packing a tensor the reference left alone stops the module tree matching the
  weights. `QuantizableWeight` is that rule, and `QuantizableWeightTests` pins it.
- Manifest layer names are the bare module paths the loader looks them up by
  (`layers.0.attention.to_q`, `model.layers.0.mlp.down_proj`), not prefixed
  with the component the way `mzbac/Z-Image-Turbo-8bit` writes them. The
  reference names never match, so its per-layer `bits` and `group_size` are
  dead and everything falls back to the top level. Bare names make mixed
  precision — a four-bit transformer with an eight-bit text encoder — actually
  work.
- Scales and biases are written float32, as the reference does, because the
  source is cast to float32 before packing. The transformer's
  `castFloatParameters` patch turns them into bfloat16 at load.

### Qwen-Image-2512: `qwen-image-2512-4bit`

**Qwen-Image-2512** (`Qwen/Qwen-Image-2512`, Apache 2.0) is a 60-layer
dual-stream MMDiT of about 20B parameters, conditioned on Qwen2.5-VL-7B and
decoded by a 3-D causal VAE. It is packed on the user's own Mac because the
release is 57.7 GB of bf16 and the four-step distillation ships separately as an
adapter, so the local build is where the two are put together; 21.6 GB on disk.
The app fetches both and packs them on first load; `make quantize-qwen` is the
same build by hand. 1024 is the default size: half the seconds of the native
1328 for an image that still renders legible text, and the entry's `peakBytes`
is measured there.

Choosing it costs 59.4 GB of download — the release and the 1.7 GB adapter,
which is what `ModelDescriptor.transferBytes` adds up and what the picker states
on a Mac that has neither; one that has the release is told the adapter's 1.7 GB
alone — and then a build. The adapter is a `ModelAdapter` on the descriptor
rather than a second catalog entry: it is one named file in a repository of its
own (that repository also ships whole merged checkpoints of twenty gigabytes
each, so it is never taken by pattern), it is not optional, and nothing
downstream of the packer ever sees one.

The full-precision source is too large for the boot volume here, so a copy of
it lives at `/Volumes/ExternalStorage/Models/Qwen-Image-2512` with the adapter
beside it in `Qwen-Image-2512-Lightning/`. Point `QWEN_SOURCE` and `QWEN_LORA`
there for `make quantize-qwen`, and `QWEN_IMAGE_SNAPSHOT` there for any test
that wants real weights. Point `MODELS_DIR` at that volume instead and the app's
own download lands there and this copy is unnecessary.

**The Lightning adapter is not optional.** The base model wants fifty steps and
real classifier-free guidance, which is two forward passes through twenty
billion parameters per step. `lightx2v/Qwen-Image-2512-Lightning` (Apache 2.0)
distils that to four steps and no guidance, and the build — the app's own, or
`make quantize-qwen` — merges it into the transformer as it packs, so the
runtime never sees an adapter. Run the same seed and prompt against a build
without it and the difference is not subtle: soft, hazy, mesh-textured surfaces
against sharp ones. That is also why the catalog entry reads
`guidanceBounds: 0...0` and `supportsNegativePrompt: false` — the merged weights
were distilled without either. An entry built from the undistilled release
would be the opposite, which is what `ModelCapabilities` being per-descriptor
is for.

The plan holds the modulation layers at eight bits while the rest goes to four.
They are 6.8 of the transformer's 20.4 billion parameters and they decide how
strongly every other layer responds; published four-bit builds that pack them
with everything else lose coherent structure. It costs about 3.4 GB on disk.

Text-to-image never runs Qwen2.5-VL's vision tower: the pipeline supplies token
ids and an attention mask and no pixels. So the ViT is not ported and its
weights are not loaded, along with `lm_head` — together 391 of the checkpoint's
729 text-encoder tensors. `WeightKeyCoverageTests` asserts that rather than
leaving it to be assumed. The autoencoder's *own* encoder is ported and loaded,
because starting from a noised copy of a picture needs it. It is half a percent
of the model, so it is built unconditionally rather than lazily: a nil module
rebuilt on demand would have to keep the shard mapped for the pipeline's whole
life to have anything to fill itself from.

### Streaming the weights

A Mac whose GPU cannot hold Qwen-Image or LTX-2.5 still runs it, by reading the
model from the disk on every step instead of holding it. The mechanism is
`LayerWeightStream` in `ZephraMLX`, and its shape is set by how MLX loads:
`MLX.loadArrays` parses a shard's header and hands back arrays that are read
with `pread` into an MLX-owned buffer only when evaluated, and there is no mmap
path (the MLX maintainers measured one and rejected it: the kernel page cache is
the wrong eviction policy for weights). So a stream keeps, per layer, the very
`MLXArray` objects the forward pass reads, and one pass does this in this order:
open fresh lazy nodes for every tensor in the stack's shards; `asyncEval` the
first `depth` layers' arrays, which starts their reads on the CPU stream; then
for each layer, run its work, `asyncEval` its outputs, **wait for the layer
before it**, then `asyncEval` the layer `depth` ahead, then hand each of the
layer's arrays a fresh unevaluated node from the next pass with
`_updateInternal`, cast back to the dtype the tree held at capture. The buffers
a layer held live exactly until its command buffers complete, and nothing has to
remember a placeholder.

Three of the loop's choices are load-bearing and easy to undo:

- The cast back is what lets a load-time cast survive streaming. The packer's
  scales are float32 on disk and MLX's quantized matmul takes its output dtype
  from them, so a stream that handed back the raw node would widen every block
  after the first to float32 from the second step on. `QwenImagePipeline.loadModel`
  casts the text encoder's and the transformer's float32 parameters to
  `QwenImageTransformerPrecision.activation` (bfloat16, or float32 under
  `ZEPHRA_DIT_DTYPE=f32`) *before* attaching either stream, `generate` casts the
  noise and the conditioning to it, and the transformer casts its text to the
  latents' dtype at entry; the autoencoder stays float32 on purpose.
- Outputs are committed per layer at all because an unevaluated graph holds
  every layer's weights as inputs, so one eval per step would read most of the
  model before any of it ran.
- The wait on the layer before is what bounds the window at `depth + 2` layers:
  MLX allocates a tensor's buffer when its read is *queued*, not when the bytes
  arrive, and a loop that queued freely would run five or six layers ahead
  before MLX's own task limit stopped it. Waiting on the layer before rather
  than the one just committed leaves the GPU a layer of work in hand.

In Qwen-Image the transformer's sixty blocks and the text encoder's
twenty-eight layers stream; the embeddings, the input and output projections,
the norms and the whole autoencoder stay resident, which is what
`QwenImageResidentParameters` evaluates at load. `QwenImagePipeline.loadModel`
takes a `QwenImageStreaming` (depth, two by default: three layers held at once)
and attaches a stream to each stack after the loader has filled it and before
anything evaluates it. A streamed step is one read of the transformer, so a
`Task.checkCancellation()` sits between blocks and Stop is answered inside a
step. Every block's tensors have identical shapes, so MLX's buffer cache hands
block i's freed buffers to block i+2's reads; the bench reports `cacheMemoryMB`
so a run where that stopped happening shows up rather than being guessed at. A
streamed image is byte for byte the resident one.

What decides it: `ModelDescriptor.streamedPeakBytes`, zero for a family that
cannot stream, is the measured peak with the weights streamed and the decode
tiled; `MemoryFit` tries it after `fitsTiled` and before giving up, and answers
`fitsStreamed`, which the picker words "Streams from disk".
`WeightResidencyPolicy` turns the Performance tab's three-way preference
(`AppSettings.weightResidency`) and the budget into a `WeightResidency` for a
load — under Automatic, streamed exactly when the verdict is `fitsStreamed`, and
never for a model with no streamed figure, which is how klein and Z-Image are
never asked to. The residency rides on
`ImageGenerationBackend.load(_:at:residency:onProgress:)`; `InferenceActor` pins
it beside `loadedPath`, so asking for a model already up the other way is a
reload, and `GenerationStore.setWeightResidencyPolicy` reloads through the swap
path when the loaded model's answer changes. `ZEPHRA_WEIGHT_RESIDENCY=streamed|resident`
overrides the preference for one launch and `ZEPHRA_STREAM_DEPTH=N` the depth;
`make bench ARGS="--stream"` measures it and prints the gigabytes read per step
and the disk's rate, which is what tells a read-bound step from a slow GPU.

**The memory budget** every verdict is measured against is `MemoryBudget` in
`ZephraCore`: not a fraction of RAM but what the GPU may keep resident, Metal's
`recommendedMaxWorkingSetSize` — 12124 MB on a 16 GB M4 mini, 38338 MB on a
48 GB M4 Max — which is the figure `sudo sysctl -w iogpu.wired_limit_mb=N`
raises. The app reads it once at launch (`GPUMemoryBudget`, from the runtime and
the sysctl) and hands it down as an environment value and to the store; MLX's
memory limit and wired limit are set from it too, so a resident model is kept in
Metal's residency set rather than left for the OS to page. Settings >
Performance shows the figure — and, on an M5-class GPU only, `GPUPrecisionNote`
saying that klein runs float32 there and why, read through
`InferenceRuntime.isM5ClassGPU()`, the one question about the GPU's generation
the app target can ask — and, when the chosen model would run with the limit
raised and does not run now, the exact command with a Copy button: the app never
runs `sudo`, and a change to the sysctl is seen at the next launch. A budget
built from RAM alone, which the tests and a GPU-less build use, assumes four
fifths of it.

### FLUX.2 klein 4B: `flux2-klein-4b-4bit`, `flux2-klein-4b-8bit`

**FLUX.2 klein 4B** (`black-forest-labs/FLUX.2-klein-4B`, Apache 2.0, ungated)
is a 3.9-billion parameter rectified-flow transformer of 5 dual-stream and 20
single-stream blocks, conditioned on Qwen3-4B and decoded by a plain 2-D KL
autoencoder, distilled to four steps with no guidance. The one download is the
bf16 release without the root single-file checkpoint, 16 GB; the app packs it
into the chosen variant on first load (`builtBytes` says what that writes), and
`make quantize-flux2` is the same build by hand. Both variants share the
download. The release is kept afterwards, because the other variant packs from
it; deleting it is a row in Settings > Models. 1024 is the default size, and the
4-bit entry is what a 16 GB Mac opens on, with the exact decode.

The text encoder is Qwen3-4B, bit for bit, and the transformer conditions on
the hidden state after its 9th, 18th and 27th layers laid side by side, padded
to 512 tokens with every position kept. So only the first 27 layers are built,
loaded, or packed; layers 27 to 35 and the final norm are omitted by the plan,
`Qwen3Model` builds `layersNeeded` layers rather than what the config says, and
`WeightKeyCoverageTests` pins the leftover set. The three modulation linears are
shared by every block of their kind and held whole: 142 million parameters is
not worth a knob. The autoencoder normalises its packed 128-channel latent with
batch-norm running statistics rather than a scaling factor, and its config
names FLUX.2-dev as its origin; only the copy inside the klein-4B repository is
ever read.

The stream runs in bfloat16, except on an M5-class GPU, where the backend runs
it float32 at about three times the step time: `Flux2ActivationPrecision` in
`ZephraBackendFlux2` resolves the dtype — `ZEPHRA_DIT_DTYPE=f32` or `bf16` if
set, else float32 when `GPUGeneration.isM5Class`, else bfloat16 — and hands it
to `Flux2Pipeline.loadModel(at:activation:)`; the kit reads no environment
variable and has no default of its own beyond bfloat16. The gate is the
workaround for the mlx-swift split-K bug (see "Conventions" in `AGENTS.md`), and it is
unverified: none of the project's Macs is an M5. The packer's float32 scales are
cast to the stream's dtype at load, without which MLX's quantized matmul widens
every activation to float32, and `Flux2ReferenceConditioning.encode` casts a
reference's tokens the same way, without which an edit widens too.

Two of this port's choices are load-bearing and easy to undo by accident. The
schedule uses the pipeline's empirical shift, not the scheduler config's
`base_shift` and `max_shift`, which klein's pipeline never reads. And the
query-key norm epsilon is the config's 1e-6, where both MIT ports use 1e-5;
`PROVENANCE.md` lists these with the other two departures.

The same checkpoint edits: a reference picture is fitted to at most a megapixel
keeping its shape, trimmed to multiples of 16, encoded, and its tokens placed
after the image being made on image index 10 of the rotary embedding's first
axis. The schedule's shift counts only the image being made. An edit is dearer
than a picture, since the reference's tokens ride through every attention layer.

### LTX-2.5: `ltx-2.5-distilled-4bit`

**LTX-2.5** (Lightricks, LTX-2.x Community License) is a 22-billion-parameter
audio-video DiT of which Zephra runs the **video stream only**: 13.1 billion
parameters across 48 blocks (video self-attention, cross-attention to text, and
a feed-forward, each gated per head by `to_gate_logits`), conditioned on a
Gemma 4 12B encoder — all 49 of its hidden states, RMS-normalised per token,
laid side by side (188160 wide), projected in float32 to 4096 and passed through
an eight-block 1-D connector, built from the DiT's own gated attention,
feed-forward, norm and rotary embedding over one axis, whose 128 learned
registers stand in for the padding — and coded by a 3-D convolutional
autoencoder (temporal x8, spatial x32, 128 latent channels), both halves of it.
Distilled to eight ancestral Euler steps (`LTX2DistilledSchedule`: nine fixed
sigmas, eta 1, re-noising drawn from `seed + 10000`) with no guidance. Frames
are `1 + 8k` at 24 fps, 9 to 121, 49 to start; sizes are multiples of 32,
768 x 512 to start.

**It makes a clip from a picture.** The autoencoder's encoder is causal in time —
the first frame repeated at the front of every convolution and nothing at the
back — so one picture encodes to one latent frame that means what it would at
the head of a longer clip, and that frame is what a reference picture is held
as. `LTX2VideoEncoder` mirrors the decoder (patch-4 patchify, 4/6/4/2/2 blocks
at 128/256/512/1024/1024 with a space-to-depth downsampler between each pair)
and is 0.64 GB of the pack's 69, loaded with everything else. Its `conv_out`
writes 129 channels and only the mean's 128 are taken, which is the
`sample_mode: "argmax"` both official pipelines encode with, and its
per-channel statistics are a different pair from the decoder's under different
names.

Holding the frame is one thing to the transformer and three to the loop.
`LTX2Transformer.callAsFunction` gains `firstFrameStrength`, and with it the
video adaLN and the output head see a **per-token** noise level,
`sigma * (1 - mask)`, while the prompt's own adaLN keeps the scalar sigma; one
held frame gives that field exactly two values, so both are computed as one
batch of two sigmas and chosen per token by the marker the keyframe embedding
already builds, row by row after the nine-row table is split.
`LTX2FirstFrameConditioning` is the rest: the loop starts from
`noise * (1 - mask) + clean * mask`, and each step converts the velocity to the
finished-latent estimate at the step's **scalar** sigma, blends the picture into
that estimate — never into the velocity, which the reference's own comment
insists on — and converts back. A frame held at strength 1 is put back after the
step, which is what the official image-to-video pipeline does by slicing it out
and never stepping it; a partly held one is left stepped. The schedule does not
change: the same nine sigmas either way. The live preview of a held run shows
the frame *after* the held one, since frame 0 is the picture that was handed in.

**The strength runs the other way**, and `LTX2RequestMapper` is the one place it
is inverted. The interface's `referenceStrength` reads as "how much of the
picture to throw away" everywhere; here the loop wants how strongly to *hold*
it, so it is `1 - strength`. The entry declares
`referenceStrengthBounds: 0.0...0.9` with a default of 0, so the default holds
the frame exactly, which is what image-to-video means, and 0.9 holds it barely.
A bound of 1 is not offered: at 1 the frame is not held at all, which is
text-to-video with an ignored picture.

**Two stages** is the reference's own route to a large frame, and `LTX2StagePlan`
in the backend decides when a clip takes it: a frame whose short edge is 512
or more and whose edges halve onto the 32-pixel grid (multiples of 64) runs the
eight-step ladder at half the size, doubles the latent through the pack's
spatial upsampler, noises the doubled latent to the second ladder's top
(`LTX2DistilledSchedule.secondStage`, `0.909375, 0.725, 0.421875, 0`) and walks
its three steps at the full size — most of a one-stage run's quality for about
three fifths of its step cost, since stage one runs on a quarter of the tokens.
`LTX2LatentUpsampler` is diffusers' `LTX2LatentUpsamplerModel` in its x2
spatial, non-rational form: a 128 to 1024 convolution, four residual blocks of
3-D convolutions and 32-group norms, a per-frame 2-D convolution folded into a
2 x 2 pixel shuffle, four more blocks and the projection back; it works in the
autoencoder's own space, so `upsample` denormalises by the decoder's
per-channel statistics on the way in and normalises on the way out. The pack
ships it as `spatial_upscaler_x2_v1_1.safetensors`, a gigabyte of bf16 already
in MLX's channels-last layout, and the plan copies it whole into an `upsampler`
component; a variant packed before it was part of the build reads as unbuilt.
A held first frame is encoded at each size, and after the noising the full-size
picture is put back over the doubled latent's first frame. The run reports the
eleven steps as one count (`LTX2StepRange`); the record still says the ladder's
eight. The temporal upsampler, the rational resampler and the tone map are not
ported. `ZEPHRA_VIDEO_STAGES=1|2` forces either for a launch.

**Lightricks' own repositories are gated.** `Lightricks/LTX-2.5` and its
diffusers layout answer 401 without a logged-in token that has clicked through
the license, and Zephra sends no token, so the catalog names the ungated
`mlx-community/ltx-2.5-mlx` pack instead: the same bf16 weights, one file per
component, `LICENSE.md` beside them. The plan reads six of its files — the
38 GB distilled transformer, the 6.3 GB connector, the 23.8 GB Gemma encoder
with its tokenizer, the 0.8 GB video decoder, the 0.64 GB video encoder a
held first frame is read by, and the 1.0 GB spatial latent upscaler the second
stage doubles the latent with — 70.6 GB in all, and omits the audio
autoencoder, the vocoder, the temporal upscaler and the dev transformer by
pattern. The gated case
is why the packed variant is published on the mirror as part of first light
and not afterwards: the mirror is the path users take, and the pack is the
fallback.

The pack is what the packer reads, so `QuantizedComponent` grew two fields for
it: `sourceFiles`, shards named relative to the release root for a component
the release keeps as one file at the top, and `sourceDirectory`, for a component
the release keeps under another name (`gemma4-12b-ltx-v1/` is written as
`text_encoder/`, configs and tokenizer copied along). Keys keep the pack's
prefixes (`transformer.`, `connector.`, `vae_decoder.`, `vae_encoder.`,
`model.language_model.`) and each kit module maps its paths onto them for the
loader, the manifest and the stream — the one real rename being the encoder's
statistics, which the pack spells `_mean_of_means` and `_std_of_means` and
mlx-swift's parameter filter would drop for the leading underscore.
`LTX2QuantizationPlan` packs both stacks at four bits and holds the
conditioning, the modulation tables (float32 in the pack), the gates and the
norms whole; the two embeddings — Gemma's 262144-row token table and the
188160-wide aggregate projection — go to eight bits, since both are read once
per prompt and both lose more than a block does at four. Every audio-side
tensor is left out by one list, `audioOmitted` (`audio`, `a2v`, `v2a`, and
`av_ca_` as a prefix under `transformer.`), so the audio variant's plan is this
plan without it; `LTX2TransformerWeights.audioMarkers` says the same words in
the kit, and `WeightKeyCoverageTests` is what keeps the two agreeing. The two
convolutional halves of the autoencoder are copied as they are, since
three-dimensional convolutions cannot be packed. At load the float32 scales are
cast to the stream's dtype for every layer but the aggregate projection, which
stays float32 because 188160 products summed in bfloat16 lose the prompt.

Video only is a real departure and not just a subset: the audio-to-video
cross-attention adds a term to the video stream that the `audio=None` forward
has not got, so this variant's pictures differ from the audio-video model's.
The official model accepts `audio=None`, the fixtures are dumped the same way,
and the seam for the audio stream — the place on `LTX2Block` where the audio
modules go, the transformer's audio heads, a second connector stack, the audio
autoencoder and vocoder, an audio track in `GeneratedVideo` — is written down
in `ROADMAP.md` for Macs with the memory. Nothing else is left out of the video
path except the temporal chunking of the decode, which matters past about 121
frames at 1024, and the H.264 re-compression the reference puts a held first
frame through before encoding it (`ROADMAP.md`).

The tokenizer is Zephra's own byte-pair encoder over the pack's `tokenizer.json`
(`LTX2Tokenizer`): swift-transformers 0.1.24 splits by grapheme cluster and
turns emoji joined by a zero-width joiner into bytes, and Swift `String` keys
merge canonically equivalent tokens, so the vocabulary is keyed by UTF-8 bytes;
the ids are pinned against Hugging Face's for twelve prompts. Gemma 4's
tokenizer emits no BOS, so the encoder prepends id 2 itself, truncates keeping
the front, and left-pads to 1024 with id 0.

Both 48-layer stacks stream through `LayerWeightStream` under
`WeightResidency.streamed`, as Qwen-Image's do; the token table, the projection,
the connector, the conditioning heads, the decoder and the encoder stay resident
(convolutions never stream). The transformer evaluates every eight blocks when
resident (`blocksPerEval`), because forty-eight blocks of a 22B model in one
Metal command buffer can outrun the watchdog on a small Mac. The live preview is
the first latent frame only of the `x - sigma * v` estimate, pooled and decoded
through the same decoder (`LTX2LatentPreview`), so a frame costs a fraction of
a step. The first forward after a load pays for Metal's kernel compilation,
which the store's warm-up run absorbs — at a price the other families do not
pay: the actor's one-step 512 picture clamps to this model's eight steps and
nine frames plus an MP4 encode (`ROADMAP.md`). The decoder has no tiled path,
so Automatic tiling changes nothing for it and `tiledPeakBytes` is the plain
peak. Nothing tells the running-run inspector a clip's length yet; it shows the
steps as it does for every family.

### Wan 2.2 TI2V-5B: `wan-2.2-ti2v-5b-4bit`

**Wan 2.2 TI2V-5B** (Alibaba's Wan team, Apache-2.0) is a 5-billion-parameter
video DiT of 30 blocks — self-attention with an RMS norm over the whole 3072-wide
query and key before the head split, cross-attention to the text, and a
GELU-tanh feed-forward, each modulated per token by a six-row scale-shift table
added to the embedded timestep — conditioned on Google's UMT5-XXL encoder (24
blocks, a relative-position bias per block, gated GELU, no attention scaling,
the last hidden state zeroed past the prompt and padded to 512 tokens) and coded
by Wan 2.2's 3-D causal convolutional autoencoder (temporal x4, spatial x16, a
pixel-unshuffle of 2 on the way in, 48 latent channels each standardised by a
published mean and deviation). Zephra runs the checkpoint FastVideo distilled
from it, **FastWan2.2-TI2V-5B**, with distribution matching to three steps at
timesteps 1000, 757 and 522 on a flow-match grid shifted by 8
(`WanDistilledSchedule`: `x0 = x - sigma * v`, then re-noised at the next sigma
with a fresh draw from `seed + 10000`), no guidance and so no negative prompt.
Frames are `1 + 4k` at 24 fps, 5 to 121, 49 to start; sizes are multiples of
32 — the autoencoder's 16 times the transformer's patch of 2 — and 832 x 480 to
start, two fifths of the trained 1280 x 704's pixels, because a step's time
grows with the token count and this is the quick family.

**It makes a clip from a picture** the way the reference's image-to-video
pipeline does with `expand_timesteps`: the encoder is causal in time, so one
picture encodes to one latent frame; the loop puts that frame in over the
sample's first frame before every forward and after every step
(`WanHeldFirstFrame.imposed`), and the transformer is told a **per-token**
timestep, 0 over the held frame's tokens and the step's everywhere else
(`WanTimestepField`), so the model sees a clean first frame at every step and
generates the rest of the clip to follow it. There is no strength: the frame is
held exactly, the entry declares `referenceStrengthBounds: 1...1`, the
interface draws no slider, and the record's strength is 1 as for a model that
conditions directly. The live preview of a held run shows the frame *after* the
held one. FastWan's distillation was text-to-video; holding a first frame under
it is the reference pipeline's mechanism applied to the distilled weights, and
`PROVENANCE.md` says so.

The release is FastVideo's Diffusers layout — `transformer/`, `text_encoder/`
in three shards with an index, `vae/`, `tokenizer/`, each with its config —
24.2 GB in all, ungated and Apache-2.0 throughout, so the catalog names it
directly and the mirror is a shortcut rather than the path. Keys are the
release's own and the kit's module paths equal them (`blocks.0.attn1.to_q`,
`encoder.block.0.layer.0.SelfAttention.q`, `encoder.down_blocks.0...`), three
renames apart in the transformer (`to_out.0`, `ffn.net.0.proj`, `ffn.net.2`,
which MLXNN cannot spell; `WanTransformerWeights`), and the convolution kernels
transposed to MLX's channels-last at load. `WanQuantizationPlan` packs both
stacks at four bits and holds the patch embedding, the modulation tables, the
output projection, UMT5's relative-position tables and the norms whole; the
transformer's `condition_embedder` — the timestep and text embedders and the
3072-by-18432 modulation projection, which decides how strongly every block
responds — and UMT5's 256384-row token table go to eight bits. The autoencoder
is copied as it is, float32, and the tokenizer directory whole.

The tokenizer is Zephra's own Unigram encoder over the release's
`tokenizer.json` (`WanTokenizer`): swift-transformers 0.1.24 aborts loading it
on a duplicate key, since Swift `String` keys merge canonically equivalent
pieces, so the vocabulary is keyed by scalars and the Viterbi walk, the
Metaspace rule and the `</s>` are the kit's; the ids are pinned against
Hugging Face's for thirty-one prompts. The prompt is cleaned first as the
reference's `prompt_clean` does — entities unescaped, whitespace collapsed —
without ftfy's mojibake repair.

Both stacks stream through `LayerWeightStream` under `WeightResidency.streamed`,
as LTX-2.5's do; the token table, the patch embedding, the conditioning, the
head and the autoencoder stay resident. The transformer evaluates every eight
blocks when resident (`blocksPerEval`). The live preview is one latent frame of
the finished-latent estimate, pooled to sixteen cells and decoded through the
same decoder (`WanLatentPreview`). The autoencoder runs in bfloat16, cast
tensor by tensor at load from the release's float32, and every causal 3-D
convolution runs as its temporal taps of 2-D convolutions one output frame at a
time (`WanCausalConv3d`): float32 and MLX's 3-D convolution cost 38 s and a
25 GB peak of a first 62 s clip, and this is 15 s and 15 GB for the same
picture. It decodes one latent frame at a time with its causal cache, and with
a tile it decodes in overlapping spatial tiles through `TiledDecode`, each tile
walking every frame with a cache of its own, so `tiledPeakBytes` is the tile's
figure; the engine's 64-cell tile is 32 of this autoencoder's cells, the same
512 pixels (`WanRequestMapper.vaeTile`).

Because it is listed before LTX-2.5 in the catalog, `ModelCatalog.animator()`
answers with it, and Animate makes its clips here.

### Packing plans

Each family's quantization plan lives in its own backend package's
`Quantization` directory; the packer they drive is shared, in
`ZephraQuantization`. Precision there is a function of the tensor name: an
ordered list of rules per component, first match wins, and a rule resolving to
no precision leaves the tensor alone. `QuantizableWeight` answers only whether
MLX *can* pack a tensor; `QuantizedComponent.precision(for:)` answers whether we
*want* it packed, and it is asked first, because the group size it names is what
divisibility is tested against.

An adapter naming weights the component has not got stops the build. That is
the one check worth keeping: an adapter written against a different port of the
same model matches nothing, merges nothing, and hands back the base model — a
failure that looks exactly like a build that worked. Its narrower twin is caught
at the file: an adapter whose tensors follow no naming `LoRAAdapter` reads —
kohya's `lora_unet_` exports, or any spelling it does not know — stops the build
with `adapterNamesNothing` before a weight is read, rather than parsing to an
adapter of nothing and "merging 0 adapted weights". And `ZephraQuantize`
refuses to build Qwen-Image without `--lora` at all
(`QuantizeFamily.requiresAdapter`): the undistilled build loads under the
distilled name and runs, and every picture is soft and hazy. `--no-lora` builds
it on purpose, and then `--out` must name a directory other than the catalog's.

Weights stream one tensor at a time out of the source shard — MLX reads each
lazily, on first evaluation, so only the tensor being packed is resident — and
spill once four gigabytes have accumulated, so a float32 transformer converts at
a fraction of its size resident. Every build takes about a minute once the
source is local, LTX-2.5 a minute and a half.


## Vendored code

`Packages/ZImageKit` is a vendored copy of `mzbac/zimage.swift` at commit
`970f83e4`. See `Packages/ZImageKit/VENDORED.md` for the license situation,
the re-sync procedure, and the running patch log. Any change inside
`ZImageKit` needs a `// ZEPHRA-PATCH:` comment and a `VENDORED.md` entry.
