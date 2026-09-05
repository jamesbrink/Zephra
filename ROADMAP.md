# Roadmap

What Zephra should build next, in order, and what was deliberately left out of the
work already done. The order was set on 3 September 2026 after FLUX.2 klein and
reference-picture editing landed; the survey behind it lives in the session notes.

Standing decisions: no CI for now (`make test` and `make test-mlx` are the gate, run
locally before every merge), and no release or distribution work until the app is
ready to ship.

## Next steps, in order

1. **Upscale with Real-ESRGAN** (shipped, PR #7). A post-process beside the
   backends; see `Packages/ZephraUpscaleRealESRGAN` and the follow-ups below.
2. **Several reference pictures at once.** klein assigns each picture its own image
   index on the rotary embedding, so this is mostly plumbing: `referenceImage` becomes
   a list capped by a new capability, the well beside the prompt becomes a row, and the
   record stores every picture. Measure the peak first; one 512 reference already lifts
   a 1024 edit to 19.2 GB.
3. **Qwen-Image-Edit-2511 with Lightning.** The strongest editor with a clean license,
   on the transformer the clean-room port already runs. Needs the Qwen2.5-VL vision
   tower the port skips today. 32 GB Macs only. Reference from mflux or mlx-gen (MIT),
   never `mzbac/qwen.image.swift` (GPL-3.0).
4. **Z-Image base**, for guidance and a negative prompt. One to three days, but 28 to
   50 steps with two passes each is about eight minutes per 1024 image on an M4 Max:
   a quality mode, not a daily one. Do it when those controls matter as features.
5. **Runtime LoRA.** Adapters are merged at build time today. A low-rank delta at
   matmul time on the quantized transformer, an adapter slot on the settings and in
   the record, a picker in the capsule. Start with klein, the smallest transformer.
6. **Hygiene.** Rerun `make bench` idle for every catalog entry and refresh the figures
   (the Qwen entry has not been re-measured since its VAE encoder was added). Try 6-bit
   or mxfp8 on Qwen-Image's 6.8B modulation weights, which cost 3.4 GB at 8-bit.

Deferred: **ERNIE-Image-Turbo** (eight to twelve days for legible in-image text at
16 GB; the Mistral3 encoder is the new work), **Boogu-Image-0.1-Turbo** (a credible
Qwen-Image successor for 32 GB Macs, still at a few hundred downloads), and
**Z-Image-Edit** (unreleased; would share the Z-Image backend).

## Downloads and model storage: left out on purpose

- **The 4-bit Z-Image variant is derived from the 32.9 GB bf16 release, not from the
  13.3 GB 8-bit download.** Both entries are the same weights at different
  precisions, and a Mac that already has the 8-bit model has to fetch two and a half
  times as much again to get the smaller one. Repacking 8-bit to 4-bit would need a
  quantized-source reader in the packer: dequantize each `.scales`/`.biases` group
  back to float, repack at the new width, and carry the manifest across. It also
  compounds the error of two quantizations, which is worth measuring against a
  straight 4-bit build before shipping. The bf16 source is the honest input, and
  disk is the cost: 32.9 GB in, 6.7 GB out, and the packer spills at 4 GB resident, so
  it runs on a 16 GB Mac but wants 40 GB free.
- **A build cannot be resumed.** `SnapshotBuild` writes into a `.partial` directory
  and removes it when the build is stopped, so a Qwen-Image build interrupted at
  nineteen of its twenty-one gigabytes starts over. Keeping it and skipping the
  components already written would need the manifest to be written per component
  rather than at the end, which is also what makes a half-built directory
  unmistakably incomplete today.
- **A download is one file at a time.** `ModelDownloader` walks the listing in
  order, so a fast connection is not saturated the way two or three concurrent
  transfers would saturate it. Sixteen gigabytes from the hub already runs near
  the line's limit here; the fix, if a slow link ever argues for it, is a task
  group with a small concurrency and one shared byte tally.
- **Only sizes are checked, not hashes.** The tree endpoint carries each LFS
  file's sha256 in `lfs.oid`, and a finished file is compared against the listed
  length and nothing else. A file that arrives complete but corrupt therefore
  loads and fails at the loader. Hashing sixteen gigabytes costs seconds, not
  minutes, so this is worth doing; it wants a streaming digest as the bytes are
  written rather than a second pass.
- **Changing the models folder moves nothing**, by design — a sixty-gigabyte
  copy is not something to start from a settings row. The last few folders the
  setting pointed at are remembered (`ModelLocations.previous`), so what was
  downloaded or built under them is still found, listed and loaded; only new
  downloads and builds go to the new folder. What is left out is the honest
  version of moving: a "move my models" button that copies, verifies, and only
  then forgets the old root.
- **Deleting a model never asks the engine to unload it first.** The row is disabled
  while the model is loaded; choosing another model frees it. A Delete that unloads
  and then trashes would be a `GenerationStore` concern, and the engine would need to
  know that a deletion is the reason it went idle.
- **Sizes are measured by walking, every time the tab opens.** Twenty files per
  model makes that instant; a cache of a thousand small repositories would not be.

## Library viewer: left out on purpose

- **Zoom and pan.** The viewer fits the whole picture to the pane, the way the canvas
  does; there is no way to look closer at one part of it. A pinch or scroll-to-zoom
  gesture, with the fitted view as the reset, is the natural next step once someone
  asks for it.
- **A filmstrip of thumbnails along the bottom**, the way Photos and Preview both
  offer, instead of only the bar's "n of N" and the prev/next buttons.

## Reference picker: left out on purpose

- **Choosing more than one picture at once.** The sheet is single-selection, and
  the well takes one reference; this waits on "several reference pictures at
  once" above, which is what would give a second picture somewhere to go.
- **Scoping the grid to an album, favourites, or a model**, the way the library
  grid's own sidebar does. The sheet always searches `.all`: a picture is picked
  here by what it looks like, and the free-text search already narrows a library
  of any size well enough to be worth the simplicity of skipping the rest of
  `LibraryQuery` for now.

## Live preview: left out on purpose

- **Latent-to-RGB factor tables.** The cheap way to show a run in progress is a 16x3
  (or 128x3) matrix that turns a latent cell straight into a pixel — no autoencoder,
  microseconds a frame, and blurry. It was not taken because the published tables are
  in GPL code (ComfyUI's `latent_preview`) and cannot be copied, so ours would have to
  be fitted: decode a few hundred latents through each family's own VAE and
  least-squares the mapping, once per family, checked in as numbers with a script
  beside them. Worth doing if the pooled decode ever proves too dear on a smaller Mac,
  or if a frame per step rather than one every 0.75 s is wanted.
- **A frame every step.** The throttle is what keeps the preview at a few percent of a
  run. Per-step frames would need the factor tables above, not a faster decode.
- **Previewing the reference-image path's first frames.** A run that starts from a
  noised copy of a picture skips the steps before its entry point, so its first frame
  is already most of the way there. Nothing is wrong with that; it is just not the
  progress bar a person expects.
- **A frame during the real decode.** The last step is deliberately not previewed: the
  full decode follows immediately, and a pooled one in front of it would be a second
  pass through the autoencoder for a picture the user is about to see properly.
- **A wall clock on the running run.** `RunningRunInspector`'s Elapsed is the steps
  that have finished at the pace they took, so it counts the loop and not the text
  encode before it, and it says nothing until the first step lands. A real clock means
  a start `Date` somewhere it survives a view being rebuilt — the store, most likely,
  which would be the first piece of interface bookkeeping in it. Not worth that for a
  line that is already right to within a step.
- **Keeping a run's frames.** Only the newest is held, and it is put down the moment
  the run ends. Scrubbing back through a run's frames, or leaving the last one up
  under the finished picture as it fades in, would mean the store keeping a strip of
  them: a quarter of a megabyte each, for something nobody has asked to look at twice.

## Upscaler follow-ups

Left out of the first pass on purpose, each a small change to one file unless noted:

- The **wdn denoise blend** and a strength slider. The weight loader already takes a
  second state dict and a blend weight; bundle `realesr-general-wdn-x4v3` and add the
  control to the inspector.
- **Download-on-demand weights** instead of the bundled 2.4 MB, if the bundle ever
  needs to shrink. Needs an availability state and a host for a converted safetensors.
- **Lanczos 2x** instead of the exact 2x2 box mean, which is what the reference tool
  does with `--outscale`. Slightly sharper, one more code path.
- **Alpha carried through.** The network is run on RGB only and the result is written
  opaque, which loses nothing for the library's own PNGs.
- **Upscaling a multi-selection**, one after another on the inference queue.
- **A sidebar timeline entry** for an upscale, beside the runs.
- **Float16 compute** if a 2048 input is measurably slow; the switch is one cast at
  load and one on the input.
- **Row-by-row joining in `TiledDecode`** for 4096 inputs, so the peak stops growing
  with the output.
- **A bench flag**, `make bench ARGS="--upscale IMAGE"`, for the same measurements the
  models get.
- **The DIV2K training-data terms.** Real-ESRGAN's repository is BSD-3-Clause and the
  weights are taken to inherit it, but the training set's own terms were not verified.
  Check before any commercial release.

## Image library location: left out on purpose

- **Merging existing libraries with conflicting files or manifests.** Folder migration
  refuses conflicts and never overwrites images or album/deletion metadata. A merge
  needs explicit choices for duplicate pictures, album identities, and deletion dates.
  For now, move into an empty folder, or keep both libraries in place and switch
  between their folders in Settings.
