# Benchmarks

Every measured figure the project relies on, with the Mac it was taken on and
what is owed a rerun. The rules those figures decide — which model a Mac is
offered, when the decode is tiled, when the weights stream — are in `AGENTS.md`
under "Model weights", and the catalog entries in
`Packages/ZephraKit/Sources/ZephraCore/Model/ModelCatalog+<Family>.swift`
carry the same figures with a comment saying where each came from. A figure
that changes here changes there in the same commit.

All figures are from `make bench` on a Release build (`ZephraBench`), seed 42
unless stated. MB are mebibytes (`MemoryUnits.mebibyte`, 2^20); GB on disk are
decimal. "Resident" is what the loaded weights hold; "peak" is the run's high
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
- Step times on record were taken on a busy machine and are not listed; a rerun
  on an idle halcyon is owed.
- Packing: about a minute once the source is local, at about 8 GB resident for
  the 24 GB float32 transformer (tensors stream out of the shard and spill at
  4 GB).

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
- Z-Image step times on an idle Mac.
- Preview frame cost for Qwen-Image and Z-Image on an idle Mac.

Benchmark on an idle machine, Release only; a figure from a busy one is a
ceiling and should say so here.
