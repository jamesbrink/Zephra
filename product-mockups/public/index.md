# Zephra — Local AI Images and Video for Mac

Zephra is a native macOS creative app powered by MLX and Metal. Generate images and short videos locally on Apple Silicon, edit images, explore variations, and organize your work in a searchable library.

Official website: https://zephra.urandom.io/

## Image creation and editing

Generate and edit images with Z-Image-Turbo, Qwen-Image-2512, or FLUX.2 klein 4B. Start with a prompt or a reference image, explore variations, and queue your next idea. Upscale still images with 2× or 4× Real-ESRGAN upscaling.

## Video and animation

LTX-2.5 generates short videos from text. Choose a picture and select Animate to use it as the first frame of a clip. Play clips in Zephra, keep them alongside your images, and export them as MP4.

Clips run at 24 fps and can be approximately five seconds long. Video generation currently produces silent clips; audio generation is not supported. Real-ESRGAN upscaling is for still images.

## Library

Use favorites, tags, albums, and search to organize your creations. Image prompts, seeds, favorites, tags, and album membership travel with the PNG. Keep a video's MP4 and poster PNG together to preserve its associated details.

## Requirements

- Apple Silicon Mac running macOS 15 or later.
- Memory and disk space appropriate for the chosen model and settings.
- An internet connection to download models. Prepare them before creating offline.

Generation speed and memory use depend on the Mac, model, resolution, and settings. FLUX.2 klein 4-bit is the smallest image model listed here and a starting point for a 16 GB Mac. LTX-2.5 and Qwen-Image can stream weights from disk via Settings > Performance to reduce memory use, with a potential speed tradeoff.

Approximate disk sizes for 4-bit models (prepared model / including retained source files): FLUX.2 klein 5.4 / 21.4 GB; Z-Image-Turbo 7.1 / 40.0 GB; Qwen-Image 21.6 / 81.0 GB; LTX-2.5 19.8 / 89.5 GB. These are disk sizes, not RAM requirements. Prepared models are downloaded when available; otherwise Zephra downloads the source and builds locally. Allow additional space for setup and your library.

## Getting started

1. Open the download, drag Zephra into Applications, and launch it there.
2. Choose an image or video model. Its first use needs a download and preparation.
3. Write a prompt and select Generate. Once the model is ready, generation works offline.

## What’s new and support

The latest website release notes highlight LTX-2.5 text-to-video and image animation, local clip playback and MP4 export, and weight streaming for Qwen-Image and LTX-2.5. [Read what’s new](https://zephra.urandom.io/#whats-new).

For help or to report a problem, email [Zephra support](mailto:dev.urandom.io@gmail.com).

## Privacy

Image and video generation run on your Mac. Zephra does not collect your prompts, images, or app activity. The app has no accounts or image uploads.

The website uses Google Analytics cookies to understand visits, download clicks, and general device and region information. This website measurement is separate from the desktop app. The website does not use this data for personalized advertising.

## Download

[Download for Mac](https://zephra-assets.urandom.io/releases/Zephra-latest.dmg)

[Current release metadata and SHA-256 checksum](https://zephra-assets.urandom.io/releases/latest.json)

## Publisher

James Brink. © 2026 James Brink. All rights reserved.
