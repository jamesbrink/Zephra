# Benchmarks

Every measured figure the project relies on, with the Mac it was taken on and
what is owed a rerun. The rules those figures decide — which model a Mac is
offered, when the decode is tiled, when the weights stream — are in `AGENTS.md`
under "Model weights", and the catalog entries in
`Packages/ZephraKit/Sources/ZephraCore/Model/ModelCatalog+<Family>.swift`
carry the same figures with a comment saying where each came from. A figure
that changes here changes there in the same commit.

All figures are from `make bench` on a Release build (`ZephraBench`), seed 42
unless stated. **MB here are decimal**: `BenchRunner` divides the allocator's
bytes by 1e6 and `BenchReport` prints that, so 23501 MB is 23.501 GB and lands
in a catalog entry as `23_500_000_000`. **Which way a figure rounds follows what
it is charged for**: a *peak* rounds up, since it is a floor on what the run
needs and a figure rounded down names a budget that does not in fact run
(6410.03 MB streamed goes in as `6_420_000_000`); a *held* figure rounds down,
since `MemoryGuard` charges a run `peak - held` and rounding the held figure up
would undercharge the transient (1336.08 MB goes in as `1_330_000_000`). GB on
disk are decimal too. Mebibytes
appear only in the `ZEPHRA_*_MB` launch variables, which are
`MemoryUnits.mebibyte`, and in a Mac's `recommendedMaxWorkingSetSize` below, as
macOS reports it. "Resident" is what the loaded weights hold; "peak" is the run's high
water mark, which the autoencoder's decode sets for a picture model; "tiled" is
the same run decoded in 64-cell latent tiles (`ZEPHRA_VAE_TILE=64`, 512-pixel
tiles), which moves a mean absolute pixel difference of 1 in 255.

Machines:

| Name | Mac | RAM | GPU working set (`recommendedMaxWorkingSetSize`) |
| --- | --- | ---: | ---: |
| halcyon | M4 Max | 48 GB | 38338 MB |
| bender | M4 mini | 16 GB | 12124 MB |

## Z-Image-Turbo

`z-image-turbo-8bit` (`mzbac/Z-Image-Turbo-8bit`, loaded as downloaded) and
`z-image-turbo-4bit` (packed here from `Tongyi-MAI/Z-Image-Turbo`, group size 64).

| Variant | Download | Built | Resident | Peak 512 | Peak 768 | Peak 1024 | Tiled 1024 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8-bit | 13.3 GB | — | 12236 MB | | | 23501 MB | 17.7 GB |
| 4-bit | 32.9 GB | 7.1 GB | 6575 MB | 10693 MB | 14599 MB | 17839 MB | 12010 MB |

- Downloads exclude `assets/`. The 4-bit tiled peak at 1024 is under bender's
  12124 MB working set, which is why a 16 GB Mac is offered that variant.
- Four bits is not faster than eight: MLX's quantized matmul costs the same at
  these shapes whichever width it packs (`make bench ARGS=--micro`), and the
  end-to-end step times agree.
- Group size 32 against 64: 825 MB more resident and 1.1 GB more on disk for no
  visible quality gain.
- Packing: about a minute once the source is local, at about 8 GB resident for
  the 24 GB float32 transformer (tensors stream out of the shard and spill at
  4 GB).

Streamed against resident, halcyon, 2026-09-13, 1024, nine steps, `--runs 3`,
`ZEPHRA_VAE_TILE=64 --stream --stream-depth 2`. The idle reading before each run
is given because halcyon was a working desktop, not a quiet lab machine: macOS's
own compositor and the apps in front of it hold it at 85-90% idle and it does not
go higher, so these are a working Mac's figures rather than a ceiling.

| Variant | Weights | Peak | Live | Load | s/step | Read per step | Disk rate | Idle |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4-bit | streamed | 6410 MB | 974 MB | 1.92 s | 7.15 | 3.40 GB | 0.43 GB/s | 87.2% |
| 4-bit | resident | 12143 MB | 6707 MB | 1.23 s | 7.51 | | | 87.9% |
| 8-bit | streamed | 6410 MB | 974 MB | 1.91 s | 7.51 | 6.79 GB | 0.94 GB/s | 87.6% |
| 8-bit | resident | 17867 MB | 12431 MB | 2.01 s | 8.03 | | | 87.6% |

- **"Read per step" is the last stream's pass only**, which is what the meter
  records: Z-Image's 30-block `layers` stack and klein's 20 single blocks, not
  the whole model. Qwen-Image's 16.15 GB row further up is the whole model,
  measured before the meter was per-stream, so the column is not comparable
  between families.
- **The two variants stream at the same peak and hold the same live figure, to
  the byte.** What the stream leaves resident is the same tensors either way —
  the float32 autoencoder, the embeddings, the norms — and the peak is those plus
  the decode's tile and the depth-2 window, none of which depends on the width
  the blocks pack at. The width is paid in reading: 6.79 GB a step at eight bits
  against 3.40 at four.
- **Streaming costs nothing here, and the 8-bit variant is faster streamed**
  (7.51 against 8.03). The M4 Max's SSD keeps up at these rates, as it does for
  LTX-2.5, and the resident 8-bit run holds 12.4 GB live where the streamed one
  holds 974 MB. Both streamed images are byte for byte their resident run's
  (`cmp` on the PNGs).
- Previews did not move the streamed peak: 6410.029146 MB with `--preview` and
  without, which the entry carries rounded **up** to 6.42 GB.
- On bender (16 GB M4 mini) the 4-bit variant measured 5196 MB peak streamed at
  1024, 22.6 s/step; its resident control was not completed and the 8-bit variant
  was not run there, at James's request. **Owed** on an idle bender.
- **The resident peaks above are 1.1% over what the catalog carries** (12143
  against 12010, 17867 against 17680) and the catalog has not been moved: 12143 MB
  is 19 MB *over* bender's 12124 MB working set, so raising `tiledPeakBytes` would
  flip a 16 GB Mac from tiling the 4-bit variant to streaming it on a 0.15%
  margin, measured on the wrong machine. The resident *live* readings are out by
  the same hand — 6707 MB against the entry's 6580 and 12431 against 12240 — and
  are left alone for the same reason. **Owed**: the same pair on bender, which
  is the Mac the verdict is about.
- The run: `ZEPHRA_VAE_TILE=64 make bench ARGS="--model z-image-turbo-8bit --size 1024 --steps 9 --runs 3 --stream --stream-depth 2"`.

## Qwen-Image-2512 4-bit

`qwen-image-2512-4bit`, packed here from the 57.7 GB bf16 release with the
1.7 GB Lightning adapter merged. 21.6 GB on disk, of which the transformer is
16.2 GB: holding the modulation layers at eight bits costs about 3.4 GB over
the 12.8 GB a pure four-bit build would write. About 269 MB per packed block.

Resident, halcyon, four steps:

| Size | Seconds | s/step | Peak | Tiled peak |
| ---: | ---: | ---: | ---: | ---: |
| 512 | 6.9 | 1.57 | 26053 MB | |
| 1024 | 33.6 | 8.15 | 30364 MB | 26068 MB |
| 1328 (native) | 66.7 | 16.25 | 32520 MB | 26088 MB |

21532 MB resident at every size. Tiled, the peak barely moves with the image,
because the tile sets the decode's transient and what is left is the
transformer. 1024 is the default size: half the seconds of native for an image
that still renders legible text, and the entry's `peakBytes` is measured there.

**Owed a rerun.** Every resident figure above was taken while the stream ran in
float32 by accident (float32 noise, uncast float32 scales, a stream handing back
raw nodes); the model runs in bfloat16 since the audit. The autoencoder's
encoder (107.2 MB of the build's 253.8 MB VAE) has been loaded since and the
figures were not adjusted by arithmetic.

Streamed (`--stream`, depth 2, tiled at 64):

| Mac | Size | Peak | Live between runs | s/step | Read per step | Disk rate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| halcyon | 1024 | 10243 MB | 1409 MB | not recorded | 16.15 GB | |
| bender | 1024 | 7954 MB | | 29.7 (123 s a picture) | | |
| bender | 512 | 5447 MB | | 7.1 | | 2.3 GB/s, read-bound |

- The halcyon streamed run was against 30473 MB resident in the same session,
  and its image was byte for byte the resident one (`cmp` on the PNGs). Its
  step time was not recorded: the machine was busy and the resident run itself
  came in at six times the catalog's figure. An idle rerun is owed.
- On bender swap did not move across either run. `dd` reads that SSD at
  1.6 GB/s in one stream; MLX's four-thread reader does better.

## FLUX.2 klein 4B

`flux2-klein-4b-4bit` and `flux2-klein-4b-8bit`, packed here from the 16 GB
bf16 release (without the root single-file checkpoint). halcyon, four steps:

| Variant | Built | Resident | Peak 512 | Peak 768 | Peak 1024 | Tiled 1024 | s/step at 512 / 768 / 1024 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 4-bit | 5.4 GB | 4941 MB | 7651 MB | 9037 MB | 12087 MB | 7660 MB | 2.1 / 4.5 / 6.9 |
| 8-bit | 8.6 GB | 8144 MB | | | 15289 MB | 10861 MB | the same |

- 1024 is the default size, and the 4-bit entry is what a 16 GB Mac opens on
  with the exact decode.
- An edit is dearer: a 1024 image from a 512 reference peaked at 19227 MB and
  took 66 s, the reference's 1024 tokens riding through every attention layer.
  **Owed a rerun**: those two figures were taken with the reference's tokens
  still float32, which widened the whole edit; `Flux2ReferenceConditioning.encode`
  now casts them to the stream's dtype.
- On an M5-class GPU the backend runs the stream float32 (see "Conventions" in
  `AGENTS.md`) at about three times the step time. Unverified: no project Mac
  is an M5.
- Packing takes about a minute.

Streamed against resident, halcyon, 2026-09-13, 1024, four steps, `--runs 3`,
`ZEPHRA_VAE_TILE=64 --stream --stream-depth 2`, with the idle reading before each
run for the reason given under Z-Image:

| Variant | Weights | Peak | Live | Load | s/step | Read per step | Disk rate | Idle |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4-bit | streamed | 4056 MB | 1336 MB | 2.24 s | 3.22 | 1.53 GB | 0.54 GB/s | 83.1% |
| 4-bit | resident | 7660 MB | 4941 MB | 0.99 s | 3.20 | | | 87.6% |
| 8-bit | streamed | 4056 MB | 1336 MB | 2.24 s | 3.43 | 2.76 GB | 0.96 GB/s | 87.8% |
| 8-bit | resident | 10863 MB | 8144 MB | 1.26 s | 3.44 | | | 85.8% |

- The two variants share a streamed peak and a live figure to the byte, as
  Z-Image's do and for the same reason: what stays resident under the stream —
  the float32 autoencoder, the embeddings, the norms and the three shared
  modulation linears — is the same in both builds, and the peak is those plus the
  decode's tile and the depth-2 window. The width shows in the reading: 2.76 GB a
  step at eight bits against 1.53 at four.
- Streaming and holding are the same pace here, within 1% either way, and the
  streamed images are byte for byte their resident runs'. A streamed load takes a
  second longer than a resident one (2.24 against 0.99) because it opens the lazy
  nodes for every tensor before the first step.
- Previews did not move the streamed peak: 4055.5967 MB either way.
- On bender both variants measured 3584 MB peak streamed, 11.57 s/step at four
  bits against 11.51 resident, and 12.13 against 12.31 at eight — the same
  "streaming is free" result on a 16 GB Mac, where the resident 8-bit build wants
  10392 MB against a 12124 MB working set. Those are single runs; **owed** in
  threes on an idle bender.
- The run: `ZEPHRA_VAE_TILE=64 make bench ARGS="--model flux2-klein-4b-4bit --size 1024 --steps 4 --runs 3 --stream --stream-depth 2"`.

## LTX-2.5 4-bit, video only

`ltx-2.5-distilled-4bit`, packed here from the 70.6 GB `mlx-community/ltx-2.5-mlx`
pack in 83 s once the pack is local. 20.84 GB out (`builtBytes`, measured:
20,839,333,747 bytes): 8.56 GB of transformer, 1.89 of connector, 8.00 of Gemma,
the 0.81 GB video decoder and 0.64 GB video encoder copied as they are, since
three-dimensional convolutions cannot be packed, and the 1.0 GB spatial
upsampler copied likewise.

Resident, halcyon, idle, 2026-09-10, with the encoder and the upsampler loaded,
768 x 512 and 49 frames:

| Stages | Seconds | s/step | Live | Peak | Load |
| --- | ---: | ---: | ---: | ---: | ---: |
| two (8 at 384 x 256, then 3) | 47.4 | 3.61 over 11 | 19155 MB | 23421 MB | 22.0 s |
| one (8 at 768 x 512) | 68.7 | 7.62 | 19155 MB | 23421 MB | 22.0 s |
| two, holding a first frame | 49.9 | 3.80 over 11 | 19155 MB | 23421 MB | |

- Two stages is what this frame takes (`LTX2StagePlan`): 31% less time for a
  clip that reads at least as well by eye (the robot the one-stage clip lost
  is there). The peak is the load's either way.
- The load is 22 s from the external volume against 4.8 s before, which is the
  disk and not the upsampler: the variant moved to `/Volumes/ExternalStorage`.
- Streamed, both stacks, the encoder and upsampler resident, holding a first
  frame in two stages: 10003 MB peak, 5737 MB live, 46.1 s a clip (the
  upsampler is the gigabyte over the 9007 MB measured before it).

Earlier, resident, eight steps in one stage, with the video encoder loaded and
no upsampler:

| Clip | Seconds | s/step | Live | Peak | Load |
| --- | ---: | ---: | ---: | ---: | ---: |
| 768 x 512, 49 frames | 63.4 | 7.0 | 18159 MB | 22425 MB | 4.8 s |
| 512 x 288, 9 frames | 10.4 | 0.90 | | the same | |

- Before the encoder was part of the load the clip held 17521 MB and peaked at
  21787 MB, so the encoder is the 638 MB between.
- The 9-frame clip's peak is the 49-frame clip's, which says the peak is the
  load's (the float32 scales before their cast) and not the decode's.
- Holding a first frame costs nothing the bench can see: 65.6 s at strength 0
  and 68.8 s at 0.6 on a busy machine, the same peak, and the text-to-video
  poster byte for byte what it was before the encoder was loaded.
- The warm-up run after a load is about ten seconds (eight steps, nine frames
  and an MP4 encode), where the picture families pay for one 512 step.

Streamed, both stacks, the encoder resident (convolutions never stream),
holding a first frame:

| Mac | Peak | Live | s/step | Clip | Read per step | Disk rate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| halcyon | 9007 MB | 4741 MB | as resident | | 8.09 GB | 1.19 GB/s |
| bender | 8284 MB | 4103 MB | 25.5 | 232 s | | 0.32 GB/s, read-bound |

- halcyon held 8369 MB peak and 4103 MB live before the encoder was loaded, and
  its streamed poster was byte for byte the resident run's. The M4 Max's SSD
  keeps up, so the pace matches resident.
- bender's run was straight after the variant landed from the mirror, and the
  first run made a coherent picture. **Owed a rerun** on an idle disk.
- The run: `make bench ARGS="--model ltx-2.5-distilled-4bit --size 768x512 --frames 49"`.

## LTX-2.5 4-bit with sound

`ltx-2.5-distilled-audio-4bit`, packed here from the same pack plus its two audio files
in 2 min 27 s once local. 25.83 GB out (`builtBytes`, measured: 25,832,161,853 bytes):
12.55 GB of transformer (the video entry's 8.56 plus the lane), 2.58 of connector (1.89
plus the audio stack and projection), the same 8.00 of Gemma, 1.47 of video autoencoder,
1.01 of upsampler, and the 0.06 GB audio decoder and 0.26 GB vocoder copied whole.

halcyon, idle, 2026-09-10, 768 x 512 and 49 frames in two stages, the MP4 carrying a
stereo AAC track at 48 kHz:

| Weights | Seconds | s/step | Live | Peak | Load | Read per step |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| resident | 112.8 | 6.98 over 11 | 24088 MB | 28711 MB | 29.7 s | |
| streamed | 84.2 | 6.20 over 11 | 7455 MB | 12078 MB | 10.3 s | 11.7 GB at 1.09 GB/s |

- Against the video-only entry's 69.4 s resident on the same day, the lane costs about
  forty seconds a clip: 5.9 billion more parameters through every block, the audio
  connector once, and the decoder and vocoder after the loop (a second or two).
- Streamed came out faster than resident on this run, which is the machine and not the
  model: the resident run was the first after the pack landed and paid for its cold
  pages, and the streamed one read a warm variant. Both are one run; **owed a rerun** in
  threes on an idle Mac.
- The peak is the load's, as it is for the video entry: 5.3 GB over it resident and
  2.1 GB streamed, the lane's blocks held or read and the audio pieces resident.
- The sound follows the prompt: a dog prompt makes one bark then near-silence in one
  stage and two barks in two, an accordion and crowd a dense track throughout; the port's
  decoder and vocoder reproduce diffusers' on the same latent with the pack's real weights
  to 0.001 in the waveform.
- The run: `make bench ARGS="--model ltx-2.5-distilled-audio-4bit --size 768x512 --frames 49"`,
  with `--stream` for the second row.

## Wan 2.2 TI2V-5B 4-bit

`wan-2.2-ti2v-5b-4bit`, packed here from the 24.2 GB
`FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers` release in 36 s once the release
is local. 10.09 GB out (`builtBytes`, measured: 10,090,839,207 bytes): 3.18 GB of
transformer (blocks at four bits, the conditioning at eight), 4.09 GB of UMT5
(blocks at four bits, the token table at eight), the 2.83 GB autoencoder copied
as it is in float32, and the tokenizer. Measured 2026-09-10 on halcyon, idle,
three steps, 832 x 480 and 49 frames, the autoencoder run in bfloat16:

| Weights | Seconds | s/step | Live | Peak | Load |
| --- | ---: | ---: | ---: | ---: | ---: |
| resident | 31.8 | 5.41 | 7996 MB | 15079 MB | 1.8 s |
| resident, tiled (engine tile 64) | 49.8 | 5.44 | 7996 MB | 12374 MB | |
| streamed, both stacks | 36.0 | 6.09 | 2625 MB | 9708 MB | 0.4 s |
| resident, holding a first frame | 37.1 | 6.24 | 7996 MB | 15079 MB | |

- The peak is the decode's, not the load's (8.8 GB) and not the transformer's
  (11.2 GB): the decoder's last stage at 240 x 416 cells of 256 channels over a
  four-frame chunk. Three things brought it down from a first 25.5 GB and 62 s:
  the autoencoder in bfloat16 rather than the release's float32 (38 s of decode
  to 29, 25.5 GB to 16.1), each causal 3-D convolution run as its temporal taps
  of 2-D convolutions (29 s to 14, since MLX's 3-D convolution unfolds on
  Metal), and one output frame convolved at a time (20.8 GB to 15.1, since the
  buffers of every convolution in a command buffer stay allocated until it has
  run). The decode is still about 15 s of the 32.
- The tile saves less here than it does the pictures, since a 512-pixel tile is
  most of a 480-pixel frame, and costs its overlap in decode time; a 16 GB Mac
  (12.1 GB working set) streams instead, which is both faster and smaller.
- The run: `make bench ARGS="--model wan-2.2-ti2v-5b-4bit --size 832x480 --frames 49"`;
  `--reference <png>` holds the picture as the first frame.

## Real-ESRGAN upscaler

A 1024 input at 4x: 2466 MB peak and 3.75 s on halcyon. 2x costs the same peak,
because it is the 4x pass followed by a box mean and the 4x join sets it.

## Live preview frames

Mean milliseconds per frame at 1024 on halcyon, against the same model's full
decode of 0.5 to 8 s:

| Model | ms per frame |
| --- | ---: |
| klein 4-bit | 43 |
| Qwen-Image 4-bit | 130 |
| Z-Image 8-bit | 192 |

The last two were taken on a busy machine and are ceilings.
`make bench ARGS="--preview --size 1024"` is the run.

## Owed reruns, in one place

- Qwen-Image resident timings and peaks in bfloat16, with the VAE encoder loaded.
- Qwen-Image streamed step time on an idle halcyon.
- klein's edit peak and time with the reference tokens cast.
- LTX-2.5 streamed on bender with an idle disk.
- Preview frame cost for Qwen-Image and Z-Image on an idle Mac.
- Z-Image's two resident peaks at 1024 on **bender**: halcyon now measures them
  1.1% over what the catalog carries, and the 4-bit figure straddles bender's own
  working set, so the catalog is not moved until the Mac the verdict is about has
  been asked. See the Z-Image "Streamed against resident" table.
- Z-Image and klein streamed against resident on bender, in threes on an idle
  machine: what is on record there is single runs, and Z-Image 8-bit was never
  run on it at all.

Benchmark on an idle machine, Release only; a figure from a busy one is a
ceiling and should say so here.
