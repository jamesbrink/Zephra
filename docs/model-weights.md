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
part-way is a row saying so, and a directory the loaded model is using cannot be
deleted from under it. Past everything the catalog claims,
`ModelStorage+Retired` sweeps every root once more and lists what is left over:
a `Downloads/<org>--<repo>` no entry names, or a variant directory carrying one
of Zephra's own stamps, `.zephra-packed-source` or `quantization.json`, which only
the packer writes. `model_index.json` is not a marker: every diffusers release
carries one, and a release somebody downloaded by hand into the models folder was
offered for deletion as a model Zephra once held. Those are
**"No longer in the catalog"** rows — deletable, never loadable — and the sweep
is careful about what it claims, skipping `.partial` directories, symbolic
links, and any folder with none of those markers, which is somebody's own. A Mac
that held a model Zephra has since dropped sees it there rather than nowhere,
which is the difference between tens of gigabytes a person can free and tens of
gigabytes they have to find. Changing the folder offers Move Models, Keep in
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
decode peaks near 23.5 GB, so 32 GB of RAM is where it runs with its weights
held. A 16 GB Mac may choose it since 2026-09-13, streamed and tiled, and the
picker says "Streams from disk"; it is not what such a Mac is started on, since
`default(fitting:)` prefers a model that fits resident and a streamed 1024
picture there is minutes rather than seconds. Always pass
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
  `castFloatParameters` patch turns them into bfloat16 at load. It evaluates
  nothing: the cast has to stay lazy for a stream to capture it and hand it back
  in that dtype on every later pass, and evaluating the tree there would read
  every streamed block off the disk and hold it. `ZImageResidentParameters.eval`
  is where a load is read in now — last of all, after the streams are attached,
  and told what is streamed.

### Qwen-Image 2.1: `qwen-image-2.1-4bit`

**Qwen-Image 2.1** (`Qwen/Qwen-Image-2.1`) is a 7.1-billion-parameter
single-stream rectified-flow transformer, conditioned on Qwen3-VL and decoded by
a four-channel autoencoder. It replaced Qwen-Image-2512 wholesale in 2026-09:
not a weights swap but three new ports, because nothing above survived the
change of architecture.

**The license is the first fact about it.** The release ships a `LICENSE`, and
it is the **Qwen RESEARCH LICENSE AGREEMENT**, which grants use "FOR
NON-COMMERCIAL PURPOSES ONLY" and defines non-commercial as "research or
evaluation purposes only". Every earlier Qwen-Image release — 1.0, Edit and
2512 — was Apache-2.0; this one is not, and nothing else in the catalog is
under a research license. Three consequences run through the code. The
`LICENSE` is in the entry's file patterns, so a download fetches it and
`SnapshotAncillaryFiles` copies it into the packed variant. The packer writes a
`NOTICE` beside it, from `QwenImage21QuantizationPlan.notice`, carrying the
attribution section 3(c) requires word for word; it is written last, so it beats
anything the release shipped. And `ModelPortrait`'s one line of copy says
non-commercial on the chooser card and in the model browser, which is the only
place a person sees the restriction before choosing to fetch 33 GB.
`THIRD_PARTY_NOTICES.md` carries the whole text and is what the Acknowledgments
window shows.

Choosing it costs **33.1 GB** of download and then a build. There is no adapter:
2.1's release is the model that runs. That is why the whole
`ModelDescriptor.adapters` seam — `ModelLocations.adapter(_:)`, the adapter rows
in Settings > Models, `LoRAAdapter` and the packer's merge — went with the entry
that replaced, which was its only user. `make prefetch-qwen21` is one call for
the same reason, and `make quantize-qwen21` takes no `--lora`.

The full-precision source is too large for the boot volume here, so a copy lives
at `$(EXTERNAL_MODELS)/Qwen-Image-2.1`. `QWEN21_MODELS` points `make
quantize-qwen21` at it, and `QWEN_IMAGE_21_SNAPSHOT` —
`TEST_RUNNER_QWEN_IMAGE_21_SNAPSHOT` under `xcodebuild` — points the kit's
release-reading suites there. Point `MODELS_DIR` at that volume instead and the
app's own download lands there and this copy is unnecessary.

#### The architecture, and what is new about it

- **One shared modulation table.** All 32 blocks read one 16384 x 4096 table
  rather than holding one each. The plan keeps it whole: it is 134 MB at
  bfloat16, so packing it saves almost nothing, and four-bit builds of the
  equivalent table in the previous architecture lost coherent structure. Held
  whole beside it: `img_in` (4096 x 64, the latent's only door in), `proj_out`
  (its only door out), the timestep embedder, `norm_out` and every norm.
  `txt_in` goes at eight bits in a four-bit build, since every text token passes
  through it once.
- **`patch_size` is 1**, so one transformer token is one latent cell and nothing
  is patchified anywhere, and there are **no biases** in the transformer at all.
- **Attention is block-causal** and is never materialised as a mask:
  `QwenImage21AttentionSegments` answers `q >= kv or same image block`, and
  `QwenImage21AttentionPlan` executes it as ordinary SDPA passes — two a layer
  on the first step, one after it.
- **The prefix KV cache is always on**, which is the reference's own default.
  One `QwenImage21KVLayerCache` a layer, head-major, committed once. It is about
  half a megabyte a prefix token, so a 1024-pixel reference is about two
  gigabytes and classifier-free guidance holds two caches. There is no switch:
  the reference's own docstring says the flag does not reproduce a picture bit
  for bit in reduced precision, so exposing it would mean recording which
  setting made every picture, or one seed would mean two pictures.
- **64 channels in and out**, matching the autoencoder's `z_dim` — four times
  the previous latent width. The autoencoder is a video autoencoder specialised
  to one frame, so the kit implements it as 2-D convolutions in 3-D-shaped
  stored kernels and never builds the six `time_conv` modules, whose twelve
  tensors it drops at load and claims by name in the coverage test. Its spatial
  factor is 16, so `QwenImage21RequestMapper` halves the engine's VAE tile on
  the way in as Wan does, flooring it at 12 cells because a tile of 8 measured
  17 dB against the untiled decode.
- **It carries alpha.** Four channels in and four out: the decode, `PixelBuffer`
  and the PNG path all carry it, a reference picture reaches the autoencoder
  with its alpha intact, and the entry declares
  `readsTransparentReferences: true` — the only one that does. Colour under a
  fully transparent pixel is *not* carried, measured at 4 to 8 dB against 38 to
  49 for the visible half; that is the model spending latent capacity correctly,
  and the kit's `PROVENANCE.md` writes it down because it looks like a broken
  port otherwise.

#### The text encoder, and the tower that is not skipped

Qwen3-VL, through a unified `Qwen3VLProcessor` rather than a tokenizer plus a
`Qwen2Tokenizer` pair. The language model is 36 layers, hidden 4096, GQA 32/8 at
head dim 128, `rope_theta` 5e6, interleaved MRoPE that collapses to one
dimension for text. `context_in_dim` is 4096.

**The vision tower is built, loaded and packed**, which is the opposite of the
model this replaced. 27 blocks, hidden 1152, three DeepStack taps at blocks 8,
16 and 24 injected after the language model's first three layers. It is what
reads a reference picture, so text-to-image alone would not need it but editing
does, and it is the one stack that never streams. What *is* left out is
`lm_head` — 1.25 GB of vocabulary projection — and the decoder's final norm,
because the pipeline takes a hidden state out of the layer stack and never
reaches a logit. `WeightKeyCoverageTests` asserts all of that rather than
leaving it assumed.

The release publishes a real `tokenizer.json`, under `processor/`, so
swift-transformers reads it directly and the assembled byte-level BPE the
previous port had to build from `vocab.json` and `merges.txt` is gone with it.

#### Steps, guidance and sizes

Forty steps on a flow-match Euler ladder with dynamic shift and the release's
exponential `time_shift_type`; `stepBounds` is 8...50. This is **not** a
distilled checkpoint, so unlike every other entry in the catalog both guidance
and a negative prompt are real: `guidanceBounds` 1...8, default 1, with the
negative prompt read wherever guidance is over one. One is the default because
the release's own card samples it that way, and because it is the value at which
the second forward pass — and its share of the prefix cache — is not paid.

Sizes are multiples of 32, a 2 x 2 patch over a 16-pixel cell, bounds
512...2752, default 1024 square, with the card's 2K set among the presets. 1344
rather than 1328: 1328 is not a multiple of 32 and was only ever legal on a
family aligned to 16.

#### What is owed

Both layer stacks stream under `WeightResidency.streamed` — the transformer's 32
blocks and the language model's 36 layers — and the tower, the autoencoder, the
embeddings, the norms and the shared modulation table stay resident.

Two figures are measured: the release is 33,131,609,424 bytes as the entry's
file patterns fetch it, and the build writes 11,564,552,844. **Every memory
figure is an estimate**, dated 2026-09-22, and the catalog entry says so at each
one. `BENCHMARKS.md` carries the run that replaces them and why
`tiledPeakBytes` is the one to read carefully: it is rounded to the side that
streams on a 16 GB Mac, and moving it under that budget is a decision made with
a reading in hand rather than a correction.

### Streaming the weights

A Mac whose GPU cannot hold a model still runs it, by reading the model from the
disk on every step instead of holding it. Every family in the catalog does this
now — LTX-2.5 first, then Wan, then Z-Image and klein as of 2026-09-13, and
Qwen-Image 2.1 from its first commit — so every entry carries a
`streamedPeakBytes` and no model
is ever loaded resident and left to page. The mechanism is
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
  after the first to float32 from the second step on. Every kit's `+Loading`
  does the four steps in the one order that works — fill the module tree, cast
  its float32 parameters to the activation dtype, attach the streams, and only
  then evaluate what is left resident — because evaluating a stack before its
  stream is attached reads the whole model in.
  `QwenImage21Pipeline+Loading` is the current example, casting to
  `QwenImage21ActivationPrecision`'s answer (bfloat16, or float32 on an
  M5-class GPU, or whatever `ZEPHRA_DIT_DTYPE` says); the autoencoders stay
  float32 on purpose.
- Outputs are committed per layer at all because an unevaluated graph holds
  every layer's weights as inputs, so one eval per step would read most of the
  model before any of it ran.
- The wait on the layer before is what bounds the window at `depth + 2` layers:
  MLX allocates a tensor's buffer when its read is *queued*, not when the bytes
  arrive, and a loop that queued freely would run five or six layers ahead
  before MLX's own task limit stopped it. Waiting on the layer before rather
  than the one just committed leaves the GPU a layer of work in hand.

The five families differ only in which stacks are handed to a stream.
Qwen-Image 2.1 is described below. LTX-2.5 and Wan stream both of their stacks.
Z-Image streams
the transformer's three (`layers`, `noise_refiner`, `context_refiner`) and the
text encoder's 36 layers; klein streams its five dual-stream blocks, its twenty
single-stream ones and the encoder's 27 layers. Two things are worth knowing
about the two newest. `Packages/ZImageKit` is vendored and now takes
`ZephraMLX` in its own manifest, logged under "Manifest changes" in its
`VENDORED.md`: a copied stream would not report into the one
`WeightStreamMeter` that `make bench --stream` and the Performance tab read, and
`LayerWeightStream` needs `ZephraCore` besides. And klein's encoder is tapped at
layers 9, 18 and 27, which the streamed pass counts inside the stream's closure
rather than trusting the order `run` hands layers back in, since `run` yields
the layer and not its index and a tap read off the wrong layer is the one thing
about this stack that a plausible picture of the wrong prompt would not give
away.

In Qwen-Image 2.1 the transformer's 32 blocks and the language model's 36
layers stream; the embeddings, the input and output projections, the norms, the
one shared modulation table, the **whole vision tower** and the whole
autoencoder stay resident, which is what `QwenImage21ResidentParameters`
evaluates at load. `QwenImage21Pipeline+Loading` takes a
`QwenImage21Streaming` (depth, two by default: three layers held at once) and
attaches a stream to each stack after the loader has filled it and before
anything evaluates it. The tower never streams because it runs once per
reference picture rather than once per step, and because a reference edit is
exactly the run that can least afford a second read of it. A streamed step is one read of the transformer, so a
`Task.checkCancellation()` sits between blocks and Stop is answered inside a
step. Every block's tensors have identical shapes, so MLX's buffer cache hands
block i's freed buffers to block i+2's reads; the bench reports `cacheMemoryMB`
so a run where that stopped happening shows up rather than being guessed at. A
streamed image is byte for byte the resident one.

What decides it: `ModelDescriptor.streamedPeakBytes` is the measured peak with the
weights streamed and the decode tiled; `MemoryFit` tries it after `fitsTiled` and
before giving up, and answers `fitsStreamed`, which the picker words "Streams
from disk". Zero there means a family that has not learned to stream, which is
resident under every mode — nothing in the catalog is that any more, so the zero
path is the rule waiting for the next family rather than a description of one.
`WeightResidencyPolicy` turns the Performance tab's three-way preference
(`AppSettings.weightResidency`) and the budget into a `WeightResidency` for a
load — under Automatic, streamed whenever the model does not fit resident,
`.tight` included, since loading a model resident *to page* is what aborted a
16 GB mini. That answer is the **static** one and stays static: it is what the
model menu's note, the Performance tab's caption and the timing keys are built
from, and all three are about what this Mac could do with this model rather than
about what it has free this minute. The live half is
`MemoryGuard.loadResidency(for:policy:tile:machine:runtime:)`, which the load
goes through: it steps a resident answer down to streamed under Automatic when
the machine has not the room for it right now, and refuses only when streaming
is short too. `MemoryGuard` is the only thing that reads the live figure, which
is why the step down lives there and not in the policy. `ModelCatalog.default(fitting:)` reads the same verdicts the other
way round and prefers a resident fit to a streamed one, because streaming is how
a Mac runs a model it cannot hold and not what a first launch should open on;
among the streamed candidates it then takes the **leanest** rather than the first
listed, since catalog order is about what a Mac holding things should see first
and decides nothing about which model is cheapest to read off a disk.
The residency rides on
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

**What the budget does not answer** is whether the memory is free *right now*, and
that is `MemoryGuard`'s (`ZephraCore/Runtime/`), asked twice per generation from
`GenerationStore+MemoryGuard`: before the weights are read in, and before a run is
started over them. It is a value type over the budget, so a refusal is a pure
function of four readings and is tested without a GPU. The machine's half comes
from an injected `MachineMemoryReader` — `HostMachineMemory` (`Sources/Zephra/Support/`)
in the app, `host_statistics64` under `HOST_VM_INFO64` with `host_page_size` for
the unit, read fresh on every call rather than once at launch, since what is going
spare between one load and the next is the whole reason the guard exists — and a
reading that cannot be had is "do not know", which leaves the budget half of the
question alone rather than guessing. Zephra's own allocator is counted back in as
free at load, because the old model is released first, and
`InferenceActor.unload()` now calls `InferenceRuntime.releaseCache()` last, after
the backend is dropped: MLX keeps a released buffer for reuse rather than handing
it back, and on halcyon those gigabytes were still charged to the process while
the next model was being measured, with a kernel panic behind it. The run check
charges only the transient — the peak less what is held — scaled linearly by
pixels times frames from the model's own default size, which is honest at that
size and optimistic a long way from it; `ROADMAP.md` carries that until a second
size is measured per family, along with the budget reserve that was considered and
left out.

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

### LTX-2.5: `ltx-2.5-distilled-4bit`, `ltx-2.5-distilled-audio-4bit`

**LTX-2.5** (Lightricks, LTX-2.x Community License) is a 22-billion-parameter
audio-video DiT. The first entry runs the **video stream only**: 13.1 billion
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
are `1 + 8k` at 24 fps, 9 to 121, 49 to start; sizes are multiples of 64 —
the autoencoder's grid is 32, but a frame that halves onto it is what the
two-stage path needs, and every fitted or typed size should take that path —
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
The official model accepts `audio=None` and the video-only fixtures are dumped
the same way. Nothing else is left out of the video path except the temporal
chunking of the decode, which matters past about 121 frames at 1024, and the
H.264 re-compression the reference puts a held first frame through before
encoding it (`ROADMAP.md`).

**The entry with sound** runs the whole model. The audio lane is 5.86 billion
more parameters: in every block an audio self-attention, an audio
cross-attention to the text, a 2048-wide feed-forward with biases, and the two
gated cross-modal attentions (audio-to-video with video queries over audio
keys, video-to-audio the other way, 32 heads of 64) on their own five-row
tables, gated and modulated by four conditioners on the transformer
(`av_ca_*_adaln_single`) that read the scalar sigma. The audio tokens are
`[1, L, 128]`, the audio autoencoder's eight channels by sixteen mel bands
packed, L = round(frames / 24 x 25), placed in seconds on a one-axis rotary
over twenty seconds (`LTX2AudioPositions`: the mel frame's midpoint at hop 160
of 16 kHz). The text reaches it through a second connector, 2048 wide with its
own 128 registers, fed by `audio_aggregate_embed`. Both lanes walk one ladder;
at the second stage the audio latent is re-noised at the ladder's top and
walked beside the doubled video, as `pipeline_ltx2_condition.py` does. After
the loop the audio latent is denormalised by the pack's per-channel statistics,
decoded by `LTX2AudioDecoder` (two-dimensional causal convolutions over
`[B, T, M, C]`, three levels of 512/256/128 with nearest doubling, pixel norm
at eps 1e-6, float32) to a two-channel mel spectrogram, and turned to sound by
`LTX2Vocoder`: BigVGAN-v2 twice, a 1536-wide generator to 16 kHz and a
512-wide bandwidth extender to 48 kHz over a Hann-windowed 3x resampling and a
convolutional mel STFT, with SnakeBeta activations anti-aliased by the pack's
stored 12-tap filters. The result is an `AudioTrack` (`ZephraMedia`) the
backend hands `MP4Writer` beside the frames, and the MP4 carries an AAC track.

The plan for it is `LTX2QuantizationPlan.plan(audio: true)`: nothing omitted
from the transformer or the connector, the lane's blocks at four bits, its
ends, adaLN heads and the four conditioners whole, the audio aggregate
projection at eight bits like the video one, and two more components copied
as they are: `audio_vae` (the decoder half and the statistics; the encoder is
left out, since nothing conditions audio) and `vocoder` (the inverse Fourier
basis left out, since nothing reads it). The variant lives under its own id
so the two identities never cross, and a Mac holding the video-only variant
packs the whole audio one beside it. Resident it holds 3.3 GB more than the
video entry; streamed it reads 3.5 GB more per step.

The tokenizer is Zephra's own byte-pair encoder over the pack's `tokenizer.json`
(`LTX2Tokenizer`): swift-transformers 0.1.24 splits by grapheme cluster and
turns emoji joined by a zero-width joiner into bytes, and Swift `String` keys
merge canonically equivalent tokens, so the vocabulary is keyed by UTF-8 bytes;
the ids are pinned against Hugging Face's for twelve prompts. Gemma 4's
tokenizer emits no BOS, so the encoder prepends id 2 itself, truncates keeping
the front, and left-pads to 1024 with id 0.

Both 48-layer stacks stream through `LayerWeightStream` under
`WeightResidency.streamed`, as every other family's do; the token table, the projection,
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

**No plan merges an adapter any more.** `LoRAAdapter`, the packer's merge step
and `ZephraQuantize`'s `--lora`, `--no-lora` and `requiresAdapter` went with
Qwen-Image-2512, their only user, when 2.1 replaced it: 2.1's release is the
model that runs. The check that went with them was worth having and is worth
writing back if a family ever needs one again — an adapter written against a
different port of the same model matches nothing, merges nothing and hands back
the base model, which is a failure that looks exactly like a build that worked.
The six surviving variants' provenance stamps are byte-identical without the
seam, so the mirror needed no re-pack.

What a plan may carry instead is a **`notice`**: a string
`SnapshotAncillaryFiles` writes as `NOTICE` beside the packed weights, last, so
it beats anything the release shipped. The release's own `LICENSE` needs no rule
at all, since a top-level file that is neither `quantization.json` nor a
`.safetensors` is copied across with the rest. Together they are what makes a
build by hand of Qwen-Image 2.1 — the app's, `make quantize-qwen21`'s or the
mirror's — as redistributable as the weights it came from, and no more.

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
