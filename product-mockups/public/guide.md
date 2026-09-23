# Zephra user guide

Beginner-friendly workflows for Zephra 0.1.0. Updated September 23, 2026.

## Make your first image

From opening Zephra to saving your first result. No technical background needed.

[Read this chapter](https://zephra.urandom.io/guide/first-image/)

### Before you start

You need a Mac with Apple Silicon (an M-series chip) and macOS 15 or later. You can check your Mac in Apple menu → About This Mac.

The app and its models are separate downloads. A model is the creative engine that turns your description into an image or video. Start with one; you can add others later. Models need several gigabytes of storage, often much more during setup.

- [Compare models and storage](https://zephra.urandom.io/guide/models/)

### Install and choose a model

1. Open the downloaded DMG and drag Zephra into Applications. Open Zephra from Applications.
2. In the first-launch model chooser, read the recommendation for your Mac. Select a model and use the button that says Download, Build, or Continue, depending on what is already available.
3. Keep your internet connection available while files download. Zephra may then prepare the model locally. This first setup takes longer than opening a prepared model.
4. If you chose Skip for Now, use Choose a Model on the canvas to return to the chooser.

### Create something simple

1. Choose an image model, such as FLUX.2 klein 4B or Z-Image Turbo, using the model menu at the top of the window.
2. Leave the small reference-image box empty. If a thumbnail is there, clear it with its × button.
3. Type the example below into the prompt box. A prompt is simply a description of what you want to see.
4. Keep the initial Size and Steps settings and choose 1 seed. Click Generate, or press Command–Return.
5. Wait until generation finishes. An in-progress preview can look blurry or unfinished; judge the completed image.

Try this prompt:

> A small copper robot reading a newspaper at a kitchen table. Morning light comes through a window on the left. A blue ceramic mug sits beside it. Warm, natural photography, eye-level view.

### Keep it or try again

Completed results are saved to your library automatically. The default folder is Pictures/Zephra. Right-click a result in Library and choose Export… to save a copy elsewhere.

To try another interpretation, right-click a generated result and choose Queue a Variation. Your previous result stays in the library.

- [Learn about prompts](https://zephra.urandom.io/guide/prompting/)
- [Organize and export your work](https://zephra.urandom.io/guide/library/)

## Choose a model

Pick the tool for your task, then let Zephra handle the technical settings.

[Read this chapter](https://zephra.urandom.io/guide/models/)

### What would you like to make?

- FLUX.2 klein 4B: create an image from words or ask for a specific change to a photo. A useful starting point for editing.
- Z-Image Turbo: make still images from a description, or reinterpret an existing picture with a Strength setting.
- Qwen-Image 2.1: make still images with legible text and dense scenes, or edit from as many as ten reference pictures at once. Its weights are under a research license for non-commercial use; the other models here are not restricted that way.
- Wan 2.2: create silent video from words or a first-frame image. Zephra includes the 5B variant.
- LTX-2.5: create video from words or a first frame. Choose “video only” for silent output or “with sound” to generate audio together with the video.

### What do 4-bit and 8-bit mean?

These describe how compactly the model is stored. A 4-bit version generally uses less storage and memory than an 8-bit version of the same model. It is a practical place to begin when your Mac has limited memory.

A larger model or variant is not automatically a better choice for every idea. Try the task with a model that fits your Mac before downloading several alternatives.

### Make room for the first download

The prepared 4-bit models use roughly 5.4 GB for FLUX.2 klein, 7.1 GB for Z-Image, 11.6 GB for Qwen-Image 2.1, 10.1 GB for Wan, 20.8 GB for LTX video only, or 25.8 GB for LTX with sound. Setup also needs source files, so allow substantially more free space.

Storage is disk space; memory is the working space your Mac uses while generating. Having enough of one does not guarantee enough of the other. Check the notes in Zephra’s model chooser and Settings → Models.

- [Full storage estimates](https://zephra.urandom.io/#dark-requirements)
- [Downloads and memory help](https://zephra.urandom.io/guide/settings/)

### Why do the controls change?

Zephra shows only settings the selected model uses. All current models have seeds. Still-image models offer Steps; video models use a fixed step schedule and instead offer Length. Qwen-Image 2.1 is the only model here that also offers Guidance and a negative prompt; the others are distilled and do not use them.

Reference images also change meaning: Start from for Z-Image, Reference for FLUX.2 klein and Qwen-Image 2.1, and First frame for video. Use the matching guide instead of copying settings from a tutorial for another app.

- [Start from an image](https://zephra.urandom.io/guide/reference-images/)
- [Edit a photo](https://zephra.urandom.io/guide/photo-editing/)
- [Make a video](https://zephra.urandom.io/guide/text-to-video/)

## Write a useful prompt

Describe the result in everyday language. Start simple, then adjust one thing at a time.

[Read this chapter](https://zephra.urandom.io/guide/prompting/)

### Describe what someone could see

Start with the main subject, then add its surroundings, light, and the type of image you want. A few concrete details are more useful than a long list of quality words. You can say “close-up” for a tight view or “wide view” to show the surroundings.

Black Forest Labs’ prompting guidance recommends a clear subject and purposeful details. You do not need special syntax to begin.

Try this prompt:

> A yellow bicycle leaning against a brick wall outside a flower shop. Overcast daylight, small puddles on the pavement, documentary photograph, wide view.

- [Upstream: building a good FLUX prompt](https://docs.bfl.ai/guides/prompting_unified_building)

### Put exact lettering in quotation marks

For a sign or poster, spell out the words and where they belong. Qwen-Image 2.1 is the model here best suited to lettering, and it is the one model with Guidance and a negative prompt when a first attempt needs correcting. Proofread the result; generated lettering can still be wrong.

Try this prompt:

> A simple illustrated poster of a lemon tree. The title at the top reads "SUNDAY MARKET" in large dark green letters. Cream background, flat screen-print style.

### Change one thing, then compare

If the idea is right but the composition is wrong, clarify the framing. If it looks too polished, describe the photographic conditions you want. Keep the seed when comparing a wording change; pick a new seed when exploring another interpretation.

A seed is a number that chooses a starting point for generation. It is useful for comparisons with the same model and settings, but is not a promise of identical results across different models, versions, or Macs.

### Adjust Qwen-Image 2.1 only when needed

Qwen-Image 2.1 starts at 40 Steps and Guidance 1. Begin there with a clear description of the finished image. Guidance above 1 has an effect only when you also enter a negative prompt; that combination runs a second pass, which can use more memory and take longer.

If a result has an unwanted feature, name it in the negative prompt in plain language, such as “blurry lettering,” then raise Guidance a little and compare with the same seed. The negative prompt is ignored at Guidance 1. Proofread any generated text after the image finishes.

### Match the wording to the task

- New image: describe the finished scene.
- Z-Image with a starting picture: describe the finished image, then adjust Strength to control how much it changes.
- Qwen-Image 2.1 with reference pictures: describe the finished image and identify which picture supplies each detail. It reads up to ten pictures in the order shown; there is no Strength setting.
- FLUX photo edit: name the change and the details to preserve.
- Video: describe what happens over time and how the camera behaves. With a first frame, focus on the movement that follows.

- [Photo-editing examples](https://zephra.urandom.io/guide/photo-editing/)
- [Video-prompt examples](https://zephra.urandom.io/guide/text-to-video/)

### About the upstream guides

These lessons adapt the model authors’ guidance to the controls in Zephra. Their websites also describe other models, cloud services, and tools that are not part of this app. Examples here are starting points to try, not guaranteed outputs.

Z-Image’s own Turbo example uses a descriptive scene and nine steps, matching Zephra’s default. You do not need the Python commands from the model card.

- [Z-Image Turbo model card](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo)
- [Qwen-Image 2.1 model card](https://huggingface.co/Qwen/Qwen-Image-2.1)
- [FLUX single-reference editing](https://docs.bfl.ai/guides/prompting_editing_single_reference)
- [LTX prompting guide](https://docs.ltx.io/open-source-model/usage-guides/prompting-guide)
- [Wan’s official prompt-expansion guidance](https://github.com/Wan-Video/Wan2.2/blob/main/wan/utils/system_prompt.py)

## Start from an image

Use a photo or drawing as the starting point for a new still image.

[Read this chapter](https://zephra.urandom.io/guide/reference-images/)

### Choose the right workflow

Use Z-Image Turbo when you want to reinterpret one picture: explore a different style, mood, or version of a scene, with a Strength setting for how far it moves. Use Qwen-Image 2.1 when you want a new image built from pictures you supply: it reads as many as ten at once, in the order you place them, and has no Strength setting. For a targeted instruction such as changing one object’s color, try FLUX.2 klein and the photo-editing guide.

- [Edit a photo with FLUX](https://zephra.urandom.io/guide/photo-editing/)

### Add your starting picture

1. Select Z-Image Turbo or Qwen-Image 2.1 in the model menu.
2. Click Start from beside the prompt, labeled Reference on Qwen-Image 2.1. Choose a picture from the library or use Choose File… for a local photo. You can also drop pictures into that box.
3. Check the thumbnails so you know which pictures will be used. Z-Image Turbo takes one picture at a time. Qwen-Image 2.1 takes as many as ten, shown as a strip you can drag to reorder, and their order changes the result.
4. Choose an output Size with the shape you want. The size menu offers choices based on the reference’s proportions; custom dimensions may be adjusted to the model’s supported sizes.

### Describe the new version

1. Describe the finished image you want rather than giving only an editing command.
2. Begin with the model’s default Steps, and on Z-Image Turbo the default Strength of 0.60. Click Generate.
3. Compare the completed result to the starting picture. On Z-Image Turbo, lower Strength to preserve more of its structure and raise it to allow a larger change. Keep the prompt and seed steady while comparing.

Try this prompt:

> A watercolor illustration of the garden path in the starting picture, with soft green foliage, delicate washes of color, and warm afternoon light. The path remains the main focus.

### Understand Strength

Strength applies to Z-Image Turbo, where it ranges from 0.10 to 0.90. It controls how much the starting picture is reworked. Low values may make very little change, especially with a small step count. High values may change the subject or composition substantially.

Qwen-Image 2.1 has no Strength setting. Like FLUX.2 klein, it conditions on your pictures directly and builds a new image from your description, so say in the prompt what should carry over.

This is a whole-image transformation. It does not protect faces, text, or selected areas. Zephra does not offer a masking brush for editing only one region.

### Combine several pictures with Qwen-Image 2.1

Add your pictures in the order you plan to describe them. The strip can hold up to ten; drag a thumbnail to change its position. In the prompt, refer to each picture by its position and say which details to keep. A few clearly assigned pictures are easier to reason about than a full strip with overlapping roles.

Each additional picture can raise memory use. If a run does not fit, try fewer references or Stream weights from disk in Settings → Performance. Qwen-Image 2.1 reads transparent references, so a cut-out can keep its alpha rather than being flattened first.

Try this prompt:

> Make a product photograph of the ceramic mug in picture 1 on the wooden table in picture 2. Keep the mug's shape and painted pattern. Use soft window light and leave the background uncluttered.

### Start another experiment

Use the × on a reference thumbnail to remove that picture; clearing the last one returns to generation from text alone. On Z-Image Turbo, right-click the thumbnail for From Library…, Choose File…, or Clear. On Qwen-Image 2.1, right-click a tile in the strip to Move Left, Move Right, Replace, or Remove it, and use the + tile to add another.

If you want to use an edited result itself as the next starting picture, export it and choose that file. Reusing a saved edit through Use as Reference can restore its original source, which is useful for trying a different edit of the same original.

- [Organize the original and results](https://zephra.urandom.io/guide/library/)

## Edit a photo

Ask for a specific change using FLUX.2 klein 4B and one reference photo.

[Read this chapter](https://zephra.urandom.io/guide/photo-editing/)

### Open the photo as a reference

1. Choose FLUX.2 klein 4B in the model menu.
2. Click Reference beside the prompt and select Choose File… or a library image. You can also drop your photo into the reference box.
3. Check the thumbnail and choose a Size with similar proportions to your photo. Keep the default four Steps for the first attempt.

### Say what changes and what stays

Name one concrete change and the important details to retain. This follows Black Forest Labs’ single-reference guidance. Zephra’s FLUX model reads the whole reference; there is no Strength slider.

Try this prompt:

> Change the blue ceramic mug to a pale green ceramic mug. Keep its shape, handle, position, the table, and the lighting the same.

- [Upstream: single-reference editing](https://docs.bfl.ai/guides/prompting_editing_single_reference)

### Try a new background

Use a photo with a clearly visible subject. Start with a simple background before asking for a complex new setting.

Try this prompt:

> Replace the background behind the vase with a plain warm gray studio backdrop. Keep the vase’s shape and painted pattern. Add a soft shadow beneath it.

### Generate and inspect the result

1. Click Generate and wait for the finished image. Your original file is not overwritten.
2. Inspect the parts you asked to keep, especially faces, lettering, edges, and small details. A request to preserve something is a direction, not a pixel-perfect guarantee.
3. If too much changes, simplify the instruction and explicitly name what matters. Try another seed before adding several more edits.
4. Export the result. To build a second edit on that result, choose the exported file as the next reference.

### What this workflow does

You can request changes to color, background, objects, or style. The model generates a new image from the photo and your instruction. Zephra currently takes one image and does not offer masks, layers, or a retouching brush.

For a looser visual reinterpretation with a Strength slider, use the starting-image workflow instead.

- [Reinterpret a photo](https://zephra.urandom.io/guide/reference-images/)
- [Upscale a finished result](https://zephra.urandom.io/guide/library/#upscale)

## Make a video from words

Create a short scene with Wan 2.2 or LTX-2.5, including sound with the LTX audio variant.

[Read this chapter](https://zephra.urandom.io/guide/text-to-video/)

### Set up a short first attempt

1. Choose Wan 2.2 or LTX-2.5 in the model menu. For audio, select LTX-2.5 “with sound.”
2. Clear any thumbnail from the First frame box so the scene starts from your words alone.
3. Keep the initial Size and choose about 2 seconds in Length. Choose 1 seed while you experiment. Longer or larger clips take more work and memory.
4. Write a prompt, then click Generate. Video models use fixed steps, so there is no Steps slider to tune.

### Give the scene something to do

Describe the setting, a clear action, and a camera position or movement. Keep the first attempt to one shot. For LTX, a short paragraph with actions in the present tense follows its authors’ guidance.

Try this prompt:

> A close view of a paper boat on a shallow pond in morning light. The boat drifts slowly from left to right as small ripples spread around it. The camera stays still, with the boat visible throughout the shot.

- [Upstream: LTX prompting guide](https://docs.ltx.io/open-source-model/usage-guides/prompting-guide)

### Add sound with LTX

Choose the “with sound” variant before generating, then describe the sounds in the same prompt. For dialogue, put the short spoken line in quotation marks and say who speaks. Keep speech brief enough for the chosen Length. The generated MP4 contains the audio.

Wan and LTX “video only” produce silent files; describing sound cannot add an audio track to those variants. Existing silent clips are not given sound by switching models afterward.

Try this prompt:

> A close-up of a glass on a wooden table. A hand sets a teaspoon beside it, making a light metallic clink. The camera remains still. Quiet room ambience is heard in the background.

### Watch the finished clip

Wait for the full generation to finish, then play the result in Zephra and use Export… to save an MP4 copy. With an audio result, check playback volume and mute settings if you cannot hear it.

Speech, timing, and synchronization can vary. Simplify the action or shorten the spoken line if the result struggles. Zephra has no audio-upload or voice-selection control.

### Make a longer clip

Length also offers longer choices that display a pass count. Zephra makes these in several connected parts and joins them into one finished clip. A pass is simply one part of that process. Start short to check your idea before committing to the longer wait.

The complete clip is saved only when all passes finish. Stop discards the unfinished run, including completed parts of that run. For changing the action between parts, extend a finished clip and write what happens next.

- [Extend a finished clip](https://zephra.urandom.io/guide/image-to-video/#extend)
- [If generation is slow](https://zephra.urandom.io/guide/settings/#memory)

## Animate an image

Turn a finished image into the opening frame of a moving scene.

[Read this chapter](https://zephra.urandom.io/guide/image-to-video/)

### Choose the first frame

1. Select Wan 2.2 or LTX-2.5. Choose LTX “with sound” if you want generated audio.
2. Click First frame beside the prompt and choose an image from the library or Choose File…. You can also drop a local image into the box.
3. Check the image’s shape against Size and begin with a short Length, such as about 2 seconds.
4. Alternatively, right-click a picture in Library and choose Animate. This prepares a video request; check the selected model and settings before generating.

### Describe the movement that follows

The image supplies the starting appearance. Concentrate on what should move and how the camera should behave. Wan’s official image-to-video prompting guidance emphasizes action instead of repeating static details already in the picture.

Try this prompt:

> The leaves sway gently in a light breeze. A few ripples move across the water. The camera stays in the same position, and the main subject remains in view.

- [Upstream: Wan prompting guidance](https://github.com/Wan-Video/Wan2.2/blob/main/wan/utils/system_prompt.py)

### Keep the starting frame close

LTX shows Strength with a first-frame image. Begin at its default of 0, which holds the conditioning frame. Raising it allows more departure from that frame; it is not a motion-speed control. Wan holds the first frame without offering a Strength slider.

The source can be resized or cropped to fit the output dimensions. Even with a held starting frame, later frames can change appearance. Keep the requested motion simple if preserving the subject is important.

### Generate and save

1. Click Generate and wait for the completed clip.
2. Play it through. If the subject changes too much, reduce the complexity of the movement, use a shorter clip, or try a new seed.
3. Use Export… on the video to save the MP4. Keep its poster PNG as well if you are moving the original library files and want the generation details.

### Continue a finished clip

1. Select a finished Zephra video and choose Extend Clip from its available actions.
2. Wait for the Continues from thumbnail to appear. Zephra prepares the end of that clip as the starting context.
3. Keep the original model and dimensions for continuity. Update the prompt to describe what happens next, and choose the length of the next part.
4. Click Generate. Zephra joins the continuation to the source and saves a new result; the original clip remains.

Animate from Last Frame starts a separate video from the end of a clip. Extend Clip joins the new part onto the existing one. Clearing or replacing the reference leaves continuation mode.

- [Video and audio tips](https://zephra.urandom.io/guide/text-to-video/)

## Keep, refine, and share

Use the library to explore variations, organize favorites, and export finished work.

[Read this chapter](https://zephra.urandom.io/guide/library/)

### Find your work

Switch to Library with Command–2; return to Canvas with Command–1. Use search to find your work and the sidebar to browse its groups. Select an item and show the inspector with Option–Command–I to review its details.

Completed results save automatically. You can browse another image while generation continues. Looking at an older image does not mean the current job has stopped.

### Explore seeds and variations

Use the shuffle control beside Seed for a different starting point. Enable Keep seed with the lock control when comparing small prompt changes. Click the seed value to enter one yourself.

The “1 seed” menu chooses how many results a press of Generate queues. Start with one, then try a small batch to compare interpretations. Right-click a generated library item and choose Queue a Variation to repeat its request with a fresh seed. Imported pictures do not have a generation request to repeat.

You can prepare and queue another idea while a generation runs. Its settings apply to the queued job, not the one already in progress.

To remove a waiting run, use the × beside it in the canvas sidebar. This removes all seeds in that waiting run.

### Organize what you like

Mark favorites and use tags and albums to collect related work. These library details live with your PNGs. For generated videos, the poster PNG carries the details while the MP4 carries the video.

Deleting an item moves it to Recently Deleted. Use Put Back to restore it within 30 days, or Delete Immediately to remove it sooner. Zephra may purge items older than 30 days; use a backup for work you need to keep.

1. Select a result in Library and mark it as a favorite from its context menu.
2. Show the inspector and use + tag to add a descriptive label, such as garden or poster.
3. Use Add to Album to choose a collection, or New Album… to create one. You can also create an empty album with New Album in the sidebar.

### Make a still image larger

1. Choose a finished still image in Library.
2. Select Upscale 2× or Upscale 4× from its available actions. Zephra may need to obtain the upscaler’s model files on first use.
3. Inspect the larger result before exporting it. Upscaling makes a new result and keeps the original.

2× doubles the width and height; 4× quadruples them. Real-ESRGAN may invent detail. This action is for still images, not video clips.

### Export or move your library

Right-click an item and choose Export… for a copy, Copy for the clipboard, or Reveal in Finder to locate the original. The app’s Share action opens macOS sharing options. Videos export as MP4; still images are PNG.

To move a video with its prompt and library details, keep its MP4 and same-named poster PNG together. Exporting the MP4 alone is convenient for sharing but does not carry the PNG’s library annotations.

Choose another library folder in Settings → General. Zephra can move the existing library or leave it where it is and switch folders. Back up the whole library folder when preserving originals, sources, albums, and deleted items.

### Useful keyboard shortcuts

- Command–Return: Generate.
- Command–period: Stop the current work.
- Command–1 / Command–2: Canvas / Library.
- Option–Command–I: show or hide the inspector.
- Shift–Command–E: export the current target.
- Shift–Command–R: reveal the current target in Finder.
- Option–Command–R: use the current target as a reference.
- Option–Command–A: prepare an animation.
- Option–Command–X: prepare an extension of a clip.

## Setup and troubleshooting

Make room for models, understand the wait, and get unstuck.

[Read this chapter](https://zephra.urandom.io/guide/settings/)

### Manage model downloads

Open Settings → Models to inspect storage and ongoing downloads. Pause keeps partial files so you can Resume later. Cancel Download discards unfinished files when no other model still needs the same transfer. Retry resumes after a failure.

Choosing another model does not necessarily cancel a background download. Some variants share files, so a transfer can continue for another model that needs it. If download controls are unavailable because the files are in use, stop the foreground work or remove queued work first.

If setup runs out of space, check the selected model-storage disk. Preparing a model needs both downloaded source files and a compact built copy. Free space or choose a larger model folder in Settings → Models; do not delete files from an active download manually.

### When generation is slow or runs out of memory

Start with a smaller Size, a shorter video Length, and one seed. Close other memory-heavy apps. Video and reference-image work can need more memory than a basic still image.

In Settings → Performance, leave Stream weights from disk on Automatic to let supported models use less memory when needed. Streaming repeatedly reads model data from storage, so slower disks can make generation slower. Qwen-Image 2.1, Wan, and LTX support it; Z-Image and FLUX stay in memory.

Tiled VAE decode in the same settings splits the final conversion into pixels into smaller pieces. Automatic is a useful default. It can reduce peak memory, with possible small differences in the result. It does not make a model’s memory needs disappear.

Scratch cache limit controls reusable temporary GPU memory. Begin with the recommended setting; Reset to Recommended restores it if you have changed it. Raising it uses more memory and is not a quality setting.

### Why is the first run taking so long?

Downloading, preparing, loading, and generating are different stages. Model files are large, and local preparation may take time after the download finishes. A prepared model can then generate without an internet connection.

The first generation after loading may also take longer while your Mac prepares GPU operations. “Warm up the model after loading” in Settings → Performance does that preparation with a throwaway run. It takes effect on the next model load.

### The result is blurry or not what I asked for

Wait for the finished result before judging an in-progress preview. Start with the model’s default Steps, where available, rather than assuming the highest number is best.

Simplify your prompt and change one setting at a time. For photo edits, check that FLUX.2 klein is selected. For Z-Image with a starting image, try lowering Strength if the original changes too much.

- [Prompt-writing help](https://zephra.urandom.io/guide/prompting/)
- [Photo-editing workflow](https://zephra.urandom.io/guide/photo-editing/)

### A control or result seems to be missing

The model determines which controls appear. Guidance and a negative prompt appear for Qwen-Image 2.1 only; the other models are distilled and do not use them. Strength appears only for models that use it and when an image is present.

If you are still looking at an older picture, check the running job or Library for the result. If a video is silent, confirm it was generated with LTX “with sound” and check the player’s volume.

### Make the workspace yours

Settings → General contains Appearance, the image-library folder, seed preferences, and notifications for work that finishes in the background. You can also hide the prompt with Option–Command–P when you want more space to view a result.

### Get help

If a problem continues, include your Mac model, macOS version, Zephra version, the selected model variant, Size and Length or Steps, and the exact error message. Add your prompt or a screenshot if you are comfortable sharing it.

- [Email Zephra support](mailto:dev.urandom.io@gmail.com?subject=Zephra%20support)
