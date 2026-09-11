# Zephra build entry points. The Xcode project is generated (gitignored); never edit it by hand.
SCHEME   := Zephra
PROJECT  := Zephra.xcodeproj
CONFIG   ?= Release
BUILD    := $(CURDIR)/build
DERIVED  := $(CURDIR)/.build/DerivedData
APP      := $(BUILD)/$(CONFIG)/Zephra.app
BENCH    := $(BUILD)/Release/ZephraBench
QUANTIZE := $(BUILD)/Release/ZephraQuantize
MODEL    := mzbac/Z-Image-Turbo-8bit

# Where the app keeps model weights: the folder Settings > Models names, with a directory per
# repository under Downloads and a directory per locally built variant beside them. Every
# prefetch writes there, so a seeded download is what the app itself would have written. Set
# MODELS_DIR to whatever the folder has been changed to in Settings.
MODELS_DIR ?= $(HOME)/Library/Application Support/Zephra/Models
DOWNLOADS  := $(MODELS_DIR)/Downloads

# `make quantize` is the build the app now does on first load, by hand: pack the bf16 release
# into the 4-bit variant. BITS and GROUP_SIZE pick the trade-off; QUANT_OUT must match
# locations.built(ModelCatalog.zImageTurbo4bit), or the app will build it again.
BASE_MODEL := Tongyi-MAI/Z-Image-Turbo
BITS       ?= 4
GROUP_SIZE ?= 64
QUANT_OUT  ?= $(MODELS_DIR)/z-image-turbo-4bit

# Qwen-Image-2512 is 57.7 GB in bf16, and the app downloads it into MODELS_DIR like any other
# release. It is too large for the boot volume here, so QWEN_SOURCE and QWEN_LORA point at
# external storage instead; set them to the app's own Downloads folders to build from what the
# app fetched. `make prefetch-qwen` seeds whichever they name.
QWEN_MODEL  := Qwen/Qwen-Image-2512
QWEN_LORA_REPO := lightx2v/Qwen-Image-2512-Lightning
# The four-step adapter in float32. The repository also ships whole merged checkpoints of twenty
# gigabytes each, which is why this names one file rather than downloading the repository.
QWEN_LORA_FILE := Qwen-Image-2512-Lightning-4steps-V1.0-fp32.safetensors
# The default is halcyon's external volume, where the 57.7 GB source lives; set QWEN_MODELS (or
# QWEN_SOURCE and QWEN_LORA directly) on any other Mac.
QWEN_MODELS ?= /Volumes/ExternalStorage/Models
QWEN_SOURCE ?= $(QWEN_MODELS)/Qwen-Image-2512
QWEN_LORA   ?= $(QWEN_MODELS)/Qwen-Image-2512-Lightning/$(QWEN_LORA_FILE)
QWEN_OUT    ?= $(MODELS_DIR)/qwen-image-2512-4bit

# FLUX.2 klein 4B is built by the app on first load, from the bf16 release in the models folder.
# `make quantize-flux2` is the same build by hand, for benchmarking and for a machine whose copy
# of the release lives elsewhere (set FLUX2_SOURCE). The root `flux-2-klein-4b.safetensors` is
# Black Forest Labs' own single-file format, 7.75 GB the loader never reads, so it is excluded.
# The output directory follows BITS, so `make quantize-flux2 BITS=8` lands in flux2-klein-4b-8bit.
FLUX2_MODEL   := black-forest-labs/FLUX.2-klein-4B
FLUX2_EXCLUDE := --exclude "flux-2-klein-4b.safetensors" --exclude "*.jpg"
FLUX2_SOURCE  ?=
FLUX2_OUT     ?= $(MODELS_DIR)/flux2-klein-4b-$(BITS)bit
# LTX-2.5 is built by the app on first load from the ungated mlx-community bf16 pack (the
# Lightricks repositories are gated, and Zephra sends no token). Only the six files the
# video-only variant reads are fetched: the distilled transformer, the connector, the Gemma 4
# encoder with its tokenizer, the convolutional video decoder and encoder, and the spatial
# latent upscaler; 70.6 GB, so LTX2_MODELS defaults
# to the external volume the way QWEN_MODELS does. `make quantize-ltx2` is the same build by hand;
# LTX2_OUT follows BITS, and a BITS other than 4 lands in a directory that is not a catalog id,
# so it gets no space check and no provenance stamp.
LTX2_MODEL   := mlx-community/ltx-2.5-mlx
LTX2_INCLUDE := --include "config.json" --include "embedded_config.json" --include "LICENSE.md" \
                --include "transformer-distilled.safetensors" --include "connector.safetensors" \
                --include "vae_decoder.safetensors" --include "vae_encoder.safetensors" \
                --include "spatial_upscaler_x2_v1_1.safetensors" \
                --include "spatial_upscaler_x2_v1_1_config.json" \
                --include "gemma4-12b-ltx-v1/*" \
                --include "audio_vae.safetensors" --include "vocoder.safetensors"
LTX2_MODELS  ?= /Volumes/ExternalStorage/Models/ZephraModels
LTX2_SOURCE  ?= $(LTX2_MODELS)/Downloads/$(subst /,--,$(LTX2_MODEL))
LTX2_OUT     ?= $(MODELS_DIR)/ltx-2.5-distilled-$(BITS)bit
# The same pack with its audio lane: the two audio files above are fetched for it, and the
# variant is packed with the lane, the audio decoder and the vocoder.
LTX2_AUDIO_OUT ?= $(MODELS_DIR)/ltx-2.5-distilled-audio-$(BITS)bit
# Wan 2.2 is built by the app on first load from FastVideo's Diffusers release of the
# three-step distilled TI2V-5B: 24 GB, so WAN_MODELS defaults to the external volume the way
# LTX2_MODELS does. `make quantize-wan` is the same build by hand.
WAN_MODEL    := FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers
WAN_INCLUDE  := --include "model_index.json" --include "README.md" --include "scheduler/*" \
                --include "text_encoder/*" --include "tokenizer/*" --include "transformer/*" \
                --include "vae/*"
WAN_MODELS   ?= /Volumes/ExternalStorage/Models/ZephraModels
WAN_SOURCE   ?= $(WAN_MODELS)/Downloads/$(subst /,--,$(WAN_MODEL))
WAN_OUT      ?= $(MODELS_DIR)/wan-2.2-ti2v-5b-$(BITS)bit
# `make mirror` builds every variant the app packs on first load into one directory that can be
# synced to a bucket as it stands: one directory per catalog id, exactly what
# `locations.built(descriptor)` holds on a Mac (provenance stamp included), plus an index.json
# listing every file with its size and SHA-256. Nothing else is written there, so
# `aws s3 sync "$(MIRROR_DIR)" s3://bucket/ --delete` mirrors it. The default is the external
# volume beside the Qwen source: four variants are 42 GB, which does not belong on a boot volume.
# A variant already stamped there is skipped; FORCE=1 rebuilds it.
# The bucket and the CloudFront host in front of it are Terraform-managed in the urandom.io
# repository (modules/zephra); the app will read https://zephra-assets.urandom.io/models/.
# MIRROR_PROFILE is the local AWS profile; CI assumes the github-actions-zephra role instead.
MIRROR_DIR          ?= $(QWEN_MODELS)/ZephraMirror
MIRROR_BUCKET       ?= s3://zephra-assets-urandom-io/models
MIRROR_PROFILE      ?= dev.urandom.io
MIRROR_DISTRIBUTION ?= E14XJ2G91C9S6D
MIRROR_AWS          := aws $(if $(MIRROR_PROFILE),--profile "$(MIRROR_PROFILE)")
MIRROR_IDS    := z-image-turbo-4bit qwen-image-2512-4bit flux2-klein-4b-4bit flux2-klein-4b-8bit \
                 ltx-2.5-distilled-4bit ltx-2.5-distilled-audio-4bit wan-2.2-ti2v-5b-4bit
# One download directory per repository, named as the app names it: <org>--<repo>.
ZIMAGE_8BIT_DIR := $(DOWNLOADS)/$(subst /,--,$(MODEL))
ZIMAGE_BASE_DIR := $(DOWNLOADS)/$(subst /,--,$(BASE_MODEL))
FLUX2_DIR       := $(DOWNLOADS)/$(subst /,--,$(FLUX2_MODEL))

DEST     := platform=macOS,arch=arm64
XCB      := xcodebuild -project "$(PROJECT)" -destination '$(DEST)' SYMROOT="$(BUILD)" -derivedDataPath "$(DERIVED)"

# The phone. A simulator *name* rather than a udid, so the same line works on any Mac; CI
# passes whatever `scripts/ios-sim.sh` found on the runner, which is the newest iPhone it has.
# PREVIEW sets ZEPHRA_PREVIEW_STATE for `run-ios`, the way ZEPHRA_PREVIEW_STATE does on the Mac.
IOS_SCHEME    := ZephraMobile
IOS_SIM       ?= iPhone 17 Pro
IOS_DEST      := platform=iOS Simulator,name=$(IOS_SIM)
IOS_APP       := $(BUILD)/Debug-iphonesimulator/Zephra.app
IOS_BUNDLE_ID := io.zephra.ZephraMobile
PREVIEW       ?=
XCB_IOS       := xcodebuild -project "$(PROJECT)" -destination '$(IOS_DEST)' SYMROOT="$(BUILD)" -derivedDataPath "$(DERIVED)"
# Every package that links MLX, and so needs xcodebuild rather than `swift test`, written as
# directory:scheme. SwiftPM names a package's scheme after the package, except where it ships
# more than one library product, when the aggregate that covers every test target is
# <name>-Package. Only ZephraMLXKit does, because a model package takes ZephraMLX without
# dragging in the quantizer.
MLX_PACKAGES := ZephraMLXKit:ZephraMLXKit-Package QwenImageKit:QwenImageKit ZephraUpscaleRealESRGAN:ZephraUpscaleRealESRGAN \
                Flux2Kit:Flux2Kit \
                ZephraBackendZImage:ZephraBackendZImage \
                ZephraBackendQwenImage:ZephraBackendQwenImage \
                ZephraBackendFlux2:ZephraBackendFlux2 \
                LTX2Kit:LTX2Kit ZephraBackendLTX2:ZephraBackendLTX2 \
                WanKit:WanKit ZephraBackendWan:ZephraBackendWan

# Distribution signing. The build itself is ad-hoc signed (project.yml), so these
# matter only to `make release` and `make notarize`. Leave SIGN_IDENTITY empty to
# take the first "Developer ID Application" identity in the keychain.
SIGN_IDENTITY  ?=
NOTARY_PROFILE ?= zephra-notary
SIGNING_CONFIG ?= $(HOME)/Documents/Zephra Signing/signing.env
RELEASE_APP    := $(BUILD)/Release/Zephra.app
RELEASE_ZIP    := $(BUILD)/Zephra.zip
RELEASE_DMG    := $(BUILD)/Zephra.dmg

# The version stamped into the app. project.yml holds the defaults an ordinary build gets;
# `make release VERSION=0.2.0 BUILD_NUMBER=42` overrides them on the xcodebuild command line
# (MARKETING_VERSION, CURRENT_PROJECT_VERSION), which is how the release workflow sets the
# marketing version from its dispatch input and the build number from the run number. Either
# may be given alone. VERSION must be MAJOR.MINOR.PATCH and BUILD_NUMBER a positive integer;
# `build` refuses anything else before xcodebuild runs, so a stray "v" never reaches a bundle.
VERSION      ?=
BUILD_NUMBER ?=
VERSION_FLAGS := $(if $(VERSION),MARKETING_VERSION=$(VERSION)) $(if $(BUILD_NUMBER),CURRENT_PROJECT_VERSION=$(BUILD_NUMBER))

.PHONY: doctor gen build run run-fresh bench quantize quantize-qwen quantize-flux2 quantize-ltx2 quantize-ltx2-audio quantize-wan mirror mirror-z-image mirror-qwen mirror-flux2-4bit mirror-flux2-8bit mirror-ltx2 mirror-ltx2-audio mirror-wan mirror-index mirror-sync prefetch prefetch-qwen prefetch-flux2 prefetch-ltx2 prefetch-wan open clean lint-layers lint-size vendored-diff logs screenshot screenshot-ios test test-app test-mlx test-backend test-ios build-ios run-ios archive-ios testflight icon signed-build release notarize notarized-release

# What a fresh Mac needs before `make build` can work, each with its fix printed.
doctor:
	@scripts/doctor.sh

gen:
	xcodegen generate --spec project.yml

build: gen
	@if [ -n "$(VERSION)" ] && ! echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; then \
	  echo "VERSION must be MAJOR.MINOR.PATCH, got '$(VERSION)'"; exit 1; fi
	@if [ -n "$(BUILD_NUMBER)" ] && ! echo "$(BUILD_NUMBER)" | grep -Eq '^[1-9][0-9]*$$'; then \
	  echo "BUILD_NUMBER must be a positive integer, got '$(BUILD_NUMBER)'"; exit 1; fi
	$(XCB) -scheme $(SCHEME) -configuration $(CONFIG) $(VERSION_FLAGS) build

run: build
	open -a "$(APP)"

# The app as somebody opening it for the first time sees it: its own preferences, its own
# models folder and its own image library, all under one throwaway directory, so nothing a
# person has downloaded, generated or set is read or written. This is how the first ten
# minutes are looked at — the empty canvas, the picker quoting a download, the fetch of a
# prebuilt variant from the mirror, the first build, the first image — and it runs beside a
# real Zephra, which the single-instance guard allows exactly because this launch shares
# neither folder with it.
#
# The directory is emptied first, since that is what "fresh" means; FRESH_RESET=0 keeps what
# is there, which is how a session is resumed without fetching gigabytes again. FRESH_DIR
# points it somewhere with room. It lives under build/, so `make clean` takes it too.
FRESH_DIR   ?= $(BUILD)/fresh
FRESH_SUITE := io.zephra.Zephra.fresh
FRESH_RESET ?= 1
run-fresh: build
	@if [ "$(FRESH_RESET)" = "1" ]; then \
	  rm -rf "$(FRESH_DIR)"; defaults delete $(FRESH_SUITE) >/dev/null 2>&1 || true; \
	  echo "fresh start: emptied $(FRESH_DIR) and the $(FRESH_SUITE) preferences"; \
	else echo "fresh start: keeping $(FRESH_DIR)"; fi
	@mkdir -p "$(FRESH_DIR)/Models" "$(FRESH_DIR)/Images"
	open -n --env ZEPHRA_FRESH_START="$(FRESH_DIR)" "$(APP)" --args -ApplePersistenceIgnoreState YES
	@echo "models: $(FRESH_DIR)/Models"
	@echo "images: $(FRESH_DIR)/Images"

# The companion, for the simulator. Debug only: there is nothing to benchmark on a phone that
# renders nothing, and the simulator takes the base ad-hoc identity, so no certificate is
# needed. The first build compiles ZephraCore, ZephraEngine and the protocol for the simulator
# from scratch, which is minutes; after that it is incremental.
build-ios: gen
	$(XCB_IOS) -scheme $(IOS_SCHEME) -configuration Debug build

# Build it, make sure the simulator is up, and launch. `make run-ios PREVIEW=pairing` launches
# it frozen in one state, which is how each surface is photographed; see `MobilePreview`.
run-ios: build-ios
	@xcrun simctl boot "$(IOS_SIM)" 2>/dev/null || true
	@xcrun simctl bootstatus "$(IOS_SIM)" -b >/dev/null
	open -a Simulator
	xcrun simctl install "$(IOS_SIM)" "$(IOS_APP)"
	@if [ -n "$(PREVIEW)" ]; then \
	  SIMCTL_CHILD_ZEPHRA_PREVIEW_STATE="$(PREVIEW)" \
	    xcrun simctl launch "$(IOS_SIM)" $(IOS_BUNDLE_ID); \
	else xcrun simctl launch "$(IOS_SIM)" $(IOS_BUNDLE_ID); fi

# The companion's own suites, hosted inside it. Seconds once the app is built.
test-ios: gen
	$(XCB_IOS) -scheme $(IOS_SCHEME) -configuration Debug \
	  -only-testing:ZephraMobileTests test

# The phone, for TestFlight. `archive-ios` builds the Release archive a device runs; the
# archive is signed automatically, and -allowProvisioningUpdates is what lets Xcode fetch the
# profile rather than be handed one -- a manual profile checked into a repository is a thing
# that expires without telling anybody.
#
# The stamping is a Mac ship's rule, for a Mac ship's reason: no version bumps, so the
# marketing version stays project.yml's 0.1.0 and what tells two builds apart is the build
# number, the UTC minute the build started. Here it is not merely a convention -- App Store
# Connect refuses a build number it has already seen, and project.yml's default of 1 would be
# refused by every upload after the first. VERSION and BUILD_NUMBER override either, with the
# same shapes `build` demands, so a stray "v" never reaches a bundle.
IOS_ARCHIVE := $(BUILD)/ZephraMobile.xcarchive
IOS_EXPORT  := $(BUILD)/testflight
# Recursive, not simple: RELEASE_STAMP is defined further down the file.
IOS_VERSION       = $(if $(VERSION),$(VERSION),0.1.0)
IOS_BUILD_NUMBER  = $(if $(BUILD_NUMBER),$(BUILD_NUMBER),$(RELEASE_STAMP))
IOS_VERSION_FLAGS = MARKETING_VERSION=$(IOS_VERSION) CURRENT_PROJECT_VERSION=$(IOS_BUILD_NUMBER)

archive-ios: gen
	@if ! echo "$(IOS_VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; then \
	  echo "VERSION must be MAJOR.MINOR.PATCH, got '$(IOS_VERSION)'"; exit 1; fi
	@if ! echo "$(IOS_BUILD_NUMBER)" | grep -Eq '^[1-9][0-9]*$$'; then \
	  echo "BUILD_NUMBER must be a positive integer, got '$(IOS_BUILD_NUMBER)'"; exit 1; fi
	rm -rf "$(IOS_ARCHIVE)"
# -allowProvisioningUpdates needs a developer account, and takes it from Xcode's Accounts
# settings or from an App Store Connect key on the command line. The key is the same one the
# export uses, so a Mac with no Apple ID signed in to Xcode can still archive; without either,
# xcodebuild says "No Accounts: Add a new account in Accounts settings". The credentials are
# passed as positional parameters rather than a string, since the path has a space in it.
	@set -a; \
	if [ -f "$(SIGNING_CONFIG)" ]; then . "$(SIGNING_CONFIG)"; fi; \
	set +a; \
	set --; \
	if [ -n "$${ASC_KEY_PATH:-}" ] && [ -n "$${ASC_KEY_ID:-}" ] && [ -n "$${ASC_ISSUER_ID:-}" ]; then \
	  set -- -authenticationKeyPath "$$ASC_KEY_PATH" -authenticationKeyID "$$ASC_KEY_ID" \
	         -authenticationKeyIssuerID "$$ASC_ISSUER_ID"; \
	  echo "archive-ios: signing with the App Store Connect key $$ASC_KEY_ID"; \
	else echo "archive-ios: no ASC_* key configured; signing with Xcode's own accounts"; fi; \
	xcodebuild archive -project "$(PROJECT)" -scheme $(IOS_SCHEME) \
	  -destination 'generic/platform=iOS' -configuration Release \
	  -archivePath "$(IOS_ARCHIVE)" -allowProvisioningUpdates \
	  -derivedDataPath "$(DERIVED)" $(IOS_VERSION_FLAGS) "$$@"
	@echo "archive-ios: $(IOS_ARCHIVE) is $(IOS_VERSION) ($(IOS_BUILD_NUMBER))"

# Export that archive straight up to App Store Connect, where it becomes a TestFlight build.
# A TestFlight upload only: releasing to the store is a separate act in App Store Connect and
# nothing here performs it. The credentials are an App Store Connect API key read from the
# same signing.env `signed-build` sources; the script refuses by name when any of the three
# ASC_* variables is unset. Internal testing needs no review, so a build reaches the phone as
# soon as App Store Connect finishes processing it.
testflight: archive-ios
	SIGNING_CONFIG="$(SIGNING_CONFIG)" ./scripts/testflight.sh "$(IOS_ARCHIVE)" "$(IOS_EXPORT)"

# The booted simulator, as a PNG under build/. The Mac's `screenshot` takes a window by its
# CoreGraphics id; a simulator has one screen, so this takes that.
screenshot-ios:
	@mkdir -p "$(BUILD)"
# simctl is refused a write onto an external volume, which is where this repository lives on
# the machine it is developed on ("Operation not permitted", with no hint as to why), so the
# picture is taken into a temporary directory and copied into build/ afterwards.
	@shot="$(BUILD)/ios-$$(date -u +%Y%m%d%H%M%S).png"; \
	  staging=$$(mktemp -d); \
	  xcrun simctl io booted screenshot "$$staging/shot.png" >/dev/null; \
	  cp "$$staging/shot.png" "$$shot"; rm -rf "$$staging"; \
	  echo "$$shot"

bench: gen
	@mkdir -p "$(BUILD)"; $(XCB) -scheme ZephraBench -configuration Release build >"$(BUILD)/ZephraBench-build.log" 2>&1 \
	  || { tail -40 "$(BUILD)/ZephraBench-build.log"; echo "ZephraBench failed to build; full log in $(BUILD)/ZephraBench-build.log"; exit 1; }
	$(BENCH) --models "$(MODELS_DIR)" $(ARGS)

# Build the 4-bit variant locally: no repository publishes Z-Image-Turbo in the manifest format
# the vendored loader reads. The download is the slow part; the quantization itself is a minute.
# The source is the --local-dir handed to `hf download`, not what the tool prints: 1.28 prints
# `path=...` where older releases printed the bare path, and a build must not depend on which.
quantize: gen
	@mkdir -p "$(BUILD)"; $(XCB) -scheme ZephraQuantize -configuration Release build >"$(BUILD)/ZephraQuantize-build.log" 2>&1 \
	  || { tail -40 "$(BUILD)/ZephraQuantize-build.log"; echo "ZephraQuantize failed to build; full log in $(BUILD)/ZephraQuantize-build.log"; exit 1; }
	hf download $(BASE_MODEL) --exclude 'assets/*' --local-dir "$(ZIMAGE_BASE_DIR)" >/dev/null
	"$(QUANTIZE)" --family z-image \
	  --source "$(ZIMAGE_BASE_DIR)" \
	  --source-name $(BASE_MODEL) --bits $(BITS) --group-size $(GROUP_SIZE) \
	  --out "$(QUANT_OUT)" $(ARGS)

# The Qwen build merges the four-step Lightning adapter into the transformer as it packs, so what
# lands in QWEN_OUT is the distilled model and the runtime never sees an adapter. The base model
# wants fifty steps and real guidance, which is two passes through twenty billion parameters per
# step; without the merge this build is unusable rather than merely slower.
quantize-qwen: gen
	@mkdir -p "$(BUILD)"; $(XCB) -scheme ZephraQuantize -configuration Release build >"$(BUILD)/ZephraQuantize-build.log" 2>&1 \
	  || { tail -40 "$(BUILD)/ZephraQuantize-build.log"; echo "ZephraQuantize failed to build; full log in $(BUILD)/ZephraQuantize-build.log"; exit 1; }
	"$(QUANTIZE)" --family qwen-image \
	  --source "$(QWEN_SOURCE)" --lora "$(QWEN_LORA)" \
	  --source-name $(QWEN_MODEL) --bits $(BITS) --group-size $(GROUP_SIZE) \
	  --out "$(QWEN_OUT)" $(ARGS)

quantize-flux2: gen
	@mkdir -p "$(BUILD)"; $(XCB) -scheme ZephraQuantize -configuration Release build >"$(BUILD)/ZephraQuantize-build.log" 2>&1 \
	  || { tail -40 "$(BUILD)/ZephraQuantize-build.log"; echo "ZephraQuantize failed to build; full log in $(BUILD)/ZephraQuantize-build.log"; exit 1; }
	@set -e; source="$(FLUX2_SOURCE)"; \
	if [ -z "$$source" ]; then hf download $(FLUX2_MODEL) $(FLUX2_EXCLUDE) --local-dir "$(FLUX2_DIR)" >/dev/null; source="$(FLUX2_DIR)"; fi; \
	"$(QUANTIZE)" --family flux2 \
	  --source "$$source" \
	  --source-name $(FLUX2_MODEL) --bits $(BITS) --group-size $(GROUP_SIZE) \
	  --out "$(FLUX2_OUT)" $(ARGS)

# The LTX-2.5 pack from LTX2_SOURCE into LTX2_OUT: the video-only 4-bit variant the catalog
# names. `make prefetch-ltx2` fetches the source first when it is not there.
quantize-ltx2: gen
	@mkdir -p "$(BUILD)"; $(XCB) -scheme ZephraQuantize -configuration Release build >"$(BUILD)/ZephraQuantize-build.log" 2>&1 \
	  || { tail -40 "$(BUILD)/ZephraQuantize-build.log"; echo "ZephraQuantize failed to build; full log in $(BUILD)/ZephraQuantize-build.log"; exit 1; }
	@test -f "$(LTX2_SOURCE)/transformer-distilled.safetensors" || $(MAKE) prefetch-ltx2
	"$(QUANTIZE)" --family ltx2 \
	  --source "$(LTX2_SOURCE)" \
	  --source-name $(LTX2_MODEL) --bits $(BITS) --group-size $(GROUP_SIZE) \
	  --out "$(LTX2_OUT)" $(ARGS)

# The same pack into LTX2_AUDIO_OUT with the audio lane, the audio decoder and the vocoder:
# the 4-bit variant with sound the catalog names.
quantize-ltx2-audio: gen
	@mkdir -p "$(BUILD)"; $(XCB) -scheme ZephraQuantize -configuration Release build >"$(BUILD)/ZephraQuantize-build.log" 2>&1 \
	  || { tail -40 "$(BUILD)/ZephraQuantize-build.log"; echo "ZephraQuantize failed to build; full log in $(BUILD)/ZephraQuantize-build.log"; exit 1; }
	@test -f "$(LTX2_SOURCE)/vocoder.safetensors" || $(MAKE) prefetch-ltx2
	"$(QUANTIZE)" --family ltx2-audio \
	  --source "$(LTX2_SOURCE)" \
	  --source-name $(LTX2_MODEL) --bits $(BITS) --group-size $(GROUP_SIZE) \
	  --out "$(LTX2_AUDIO_OUT)" $(ARGS)

# The FastWan release from WAN_SOURCE into WAN_OUT: the 4-bit variant the catalog names.
# `make prefetch-wan` fetches the source first when it is not there.
quantize-wan: gen
	@mkdir -p "$(BUILD)"; $(XCB) -scheme ZephraQuantize -configuration Release build >"$(BUILD)/ZephraQuantize-build.log" 2>&1 \
	  || { tail -40 "$(BUILD)/ZephraQuantize-build.log"; echo "ZephraQuantize failed to build; full log in $(BUILD)/ZephraQuantize-build.log"; exit 1; }
	@test -f "$(WAN_SOURCE)/transformer/diffusion_pytorch_model.safetensors" || $(MAKE) prefetch-wan
	"$(QUANTIZE)" --family wan \
	  --source "$(WAN_SOURCE)" \
	  --source-name $(WAN_MODEL) --bits $(BITS) --group-size $(GROUP_SIZE) \
	  --out "$(WAN_OUT)" $(ARGS)

# The mirror: one directory per packed variant, named for its catalog id so ZephraQuantize
# checks the volume for that entry's builtBytes and stamps its provenance, then index.json.
# Each variant is its own target, so one can be rebuilt alone; the sources are the same
# releases the quantize targets read (ZIMAGE_BASE_DIR and FLUX2_DIR are fetched if absent,
# QWEN_SOURCE and QWEN_LORA must already be there).
mirror: mirror-z-image mirror-qwen mirror-flux2-4bit mirror-flux2-8bit mirror-ltx2 mirror-ltx2-audio mirror-wan mirror-index

mirror-z-image:
	@$(call mirror_variant,z-image-turbo-4bit,quantize QUANT_OUT="$(MIRROR_DIR)/z-image-turbo-4bit" BITS=4)

mirror-qwen:
	@$(call mirror_variant,qwen-image-2512-4bit,quantize-qwen QWEN_OUT="$(MIRROR_DIR)/qwen-image-2512-4bit" BITS=4)

mirror-flux2-4bit:
	@$(call mirror_variant,flux2-klein-4b-4bit,quantize-flux2 FLUX2_OUT="$(MIRROR_DIR)/flux2-klein-4b-4bit" BITS=4)

mirror-flux2-8bit:
	@$(call mirror_variant,flux2-klein-4b-8bit,quantize-flux2 FLUX2_OUT="$(MIRROR_DIR)/flux2-klein-4b-8bit" BITS=8)

mirror-ltx2:
	@$(call mirror_variant,ltx-2.5-distilled-4bit,quantize-ltx2 LTX2_OUT="$(MIRROR_DIR)/ltx-2.5-distilled-4bit" BITS=4)

mirror-ltx2-audio:
	@$(call mirror_variant,ltx-2.5-distilled-audio-4bit,quantize-ltx2-audio LTX2_AUDIO_OUT="$(MIRROR_DIR)/ltx-2.5-distilled-audio-4bit" BITS=4)

mirror-wan:
	@$(call mirror_variant,wan-2.2-ti2v-5b-4bit,quantize-wan WAN_OUT="$(MIRROR_DIR)/wan-2.2-ti2v-5b-4bit" BITS=4)

# Skips a variant whose provenance stamp is already in the mirror, unless FORCE=1; the packer
# would otherwise empty and rewrite it. $(1) is the catalog id, $(2) the quantize invocation.
define mirror_variant
if [ -z "$(FORCE)" ] && [ -f "$(MIRROR_DIR)/$(1)/.zephra-packed-source" ]; then \
  echo "mirror: $(1) is already built in $(MIRROR_DIR); FORCE=1 rebuilds it"; \
else \
  mkdir -p "$(MIRROR_DIR)" && $(MAKE) $(2); \
fi
endef

# index.json over whatever variants the mirror holds: every file's path, size and SHA-256, so
# a client can list a variant without a bucket listing and verify what it fetched. Run alone
# after a hand-made change; `make mirror` runs it last.
mirror-index:
	swift scripts/mirror-index.swift "$(MIRROR_DIR)" $(MIRROR_IDS)

# Push the mirror to MIRROR_BUCKET (s3://name/prefix) under MIRROR_PROFILE, or under whatever
# credentials the environment holds when MIRROR_PROFILE is empty (CI). --delete keeps the
# prefix the mirror's image; without it a variant renamed here would linger there, which is
# also why the prefix is `models` and not the bucket root. Nothing but the mirror directory
# is read, and index.json goes last so a client never sees an index ahead of its files.
# is read, and index.json goes last so a client never sees an index ahead of its files; the
# CloudFront invalidation then drops the cached copy of the one key that changes in place.
mirror-sync:
	@test -n "$(MIRROR_BUCKET)" || { echo "set MIRROR_BUCKET=s3://bucket/prefix"; exit 2; }
	$(MIRROR_AWS) s3 sync "$(MIRROR_DIR)" "$(MIRROR_BUCKET)" --delete --exclude ".DS_Store" --exclude "index.json" --no-progress
	$(MIRROR_AWS) s3 cp "$(MIRROR_DIR)/index.json" "$(MIRROR_BUCKET)/index.json" --no-progress
	@test -z "$(MIRROR_DISTRIBUTION)" || $(MIRROR_AWS) cloudfront create-invalidation \
	  --distribution-id "$(MIRROR_DISTRIBUTION)" --paths "/models/index.json" --output text --query 'Invalidation.Id'


test:
	cd Packages/ZephraKit && swift test

# The app target's own suites (Tests/ZephraTests), hosted inside the Debug app so they can
# `@testable import Zephra`; Release turns ENABLE_TESTABILITY off. The first run builds the
# Debug app, which compiles MLX's Metal kernels from scratch and takes several minutes; after
# that it is an incremental link plus the tests. The host launches with
# ZEPHRA_PREVIEW_STATE=ready (set on the scheme), so no model is loaded under the tests.
test-app: gen
	$(XCB) -scheme $(SCHEME) -configuration Debug -skipPackagePluginValidation \
	  -only-testing:ZephraTests test

# These link MLX, so their tests need xcodebuild rather than `swift test`. Kept out of
# `make test` on purpose: that one stays MLX-free and fast. Serial, because the parity
# suites share one GPU and one MLX default stream: run in parallel, whichever autoencoder
# suite lands beside a heavy one reads back a tensor off by whole units.
test-mlx:
	@for entry in $(MLX_PACKAGES); do \
	  package=$${entry%%:*}; scheme=$${entry##*:}; \
	  echo "== $$package"; \
	  ( cd $(CURDIR)/Packages/$$package && xcodebuild test -scheme $$scheme \
	    -destination 'platform=macOS' -skipPackagePluginValidation \
	    -parallel-testing-enabled NO -derivedDataPath $(DERIVED) ) || exit 1; \
	done

# The name this had when there was one such package.
test-backend: test-mlx

icon:
	swift scripts/make-icon.swift

# Build and sign the app for distribution. If present, SIGNING_CONFIG is sourced
# before signing so a local machine can keep its identity selection in Documents.
signed-build:
	$(MAKE) CONFIG=Release VERSION="$(VERSION)" BUILD_NUMBER="$(BUILD_NUMBER)" build
	@set -a; \
	if [ -f "$(SIGNING_CONFIG)" ]; then . "$(SIGNING_CONFIG)"; fi; \
	set +a; \
	if [ -n "$(SIGN_IDENTITY)" ]; then SIGN_IDENTITY="$(SIGN_IDENTITY)"; fi; \
	export SIGN_IDENTITY; \
	./scripts/sign-release.sh "$(RELEASE_APP)"

# Package the signed app as a ZIP and a signed DMG. Notarization is separate;
# distribution signatures use Apple secure timestamps. VERSION and BUILD_NUMBER
# (above) stamp the bundle; without them the build carries project.yml's defaults.
release: signed-build
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --keepParent "$(RELEASE_APP)" "$(RELEASE_ZIP)"
	@set -a; \
	if [ -f "$(SIGNING_CONFIG)" ]; then . "$(SIGNING_CONFIG)"; fi; \
	set +a; \
	if [ -n "$(SIGN_IDENTITY)" ]; then SIGN_IDENTITY="$(SIGN_IDENTITY)"; fi; \
	export SIGN_IDENTITY; \
	./scripts/create-dmg.sh "$(RELEASE_APP)" "$(RELEASE_DMG)"
	@echo "release: $(RELEASE_DMG) and $(RELEASE_ZIP) are ready for 'make notarize'"

# Submit to Apple, staple the ticket, repackage. Needs credentials stored once:
#   xcrun notarytool store-credentials $(NOTARY_PROFILE) \
#       --apple-id <apple id> --team-id <team id> --password <app-specific password>
notarize:
	@set -a; \
	if [ -f "$(SIGNING_CONFIG)" ]; then . "$(SIGNING_CONFIG)"; fi; \
	set +a; \
	if [ -n "$(NOTARY_PROFILE)" ]; then NOTARY_PROFILE="$(NOTARY_PROFILE)"; fi; \
	if [ -n "$(SIGN_IDENTITY)" ]; then SIGN_IDENTITY="$(SIGN_IDENTITY)"; fi; \
	export NOTARY_PROFILE SIGN_IDENTITY; \
	./scripts/notarize-release.sh "$(RELEASE_APP)" "$(RELEASE_ZIP)" "$(RELEASE_DMG)"

# Keep notarization after packaging even when make is invoked with -j.
notarized-release: release
	$(MAKE) notarize

# Into the app's own folder, under the name the app would have given it, so a first launch
# finds the download rather than fetching it again.
prefetch:
	hf download $(MODEL) --exclude "assets/*" --local-dir "$(ZIMAGE_8BIT_DIR)"

# Qwen-Image-2512 and its four-step adapter, onto QWEN_MODELS rather than into MODELS_DIR:
# 57.7 GB does not belong on a boot volume. The app downloads the same two things itself, into
# $(DOWNLOADS)/Qwen--Qwen-Image-2512 and $(DOWNLOADS)/lightx2v--Qwen-Image-2512-Lightning, so
# point MODELS_DIR at a roomy volume and this target is unnecessary; it stays for keeping the
# build source apart from the folder the app manages.
prefetch-qwen:
	hf download $(QWEN_MODEL) --local-dir "$(QWEN_SOURCE)"
	hf download $(QWEN_LORA_REPO) $(QWEN_LORA_FILE) \
	  --local-dir "$(QWEN_MODELS)/Qwen-Image-2512-Lightning"

# The klein release into the app's own folder, which is where it looks before it downloads.
prefetch-flux2:
	hf download $(FLUX2_MODEL) $(FLUX2_EXCLUDE) --local-dir "$(FLUX2_DIR)"

# The LTX-2.5 files both builds read — the five the video-only one packs and the two audio
# files the entry with sound adds — into LTX2_MODELS' Downloads folder as the app would
# name it; point MODELS_DIR at that volume and the app finds them.
prefetch-ltx2:
	hf download $(LTX2_MODEL) $(LTX2_INCLUDE) --local-dir "$(LTX2_SOURCE)"

prefetch-wan:
	hf download $(WAN_MODEL) $(WAN_INCLUDE) --local-dir "$(WAN_SOURCE)"

open: gen
	open $(PROJECT)

clean:
	rm -rf "$(BUILD)" "$(DERIVED)" "$(PROJECT)"

logs:
	log stream --style compact --predicate 'subsystem == "io.zephra"'

# WINDOW=<title> photographs the window with that title instead of the largest one, which is
# how a Settings tab is captured: `make screenshot WINDOW=General`.
screenshot:
	WINDOW="$(WINDOW)" ./scripts/screenshot.sh

# Every hunk of the vendored ZImageKit that differs from upstream at the pinned commit must
# carry a ZEPHRA-PATCH marker; this fetches upstream into a scratch clone and checks. Run it
# after a re-sync, and before committing a change under Packages/ZImageKit.
vendored-diff:
	./scripts/vendored-diff.sh --check

# Layering rules from CLAUDE.md, enforced mechanically. FAMILIES is the one list a new family
# is added to; the import patterns name the kits' module names, which are the same words.
FAMILIES := ZImage QwenImage Flux2 LTX2 Wan
lint-layers:
	@! grep -rlnE '^import (ZImage|QwenImage|Flux2|LTX2|Wan|MLX)' Sources/Zephra Sources/ZephraMobile Sources/ZephraBench Sources/ZephraQuantize --include='*.swift' \
	  || (echo "LAYER VIOLATION: app or tool target imports a model package or MLX directly"; exit 1)
	@! grep -rlnE '^import (ZephraBackend|ZephraUpscale|ZephraMedia)' Sources/Zephra --include='*.swift' | grep -v 'ZephraApp.swift' \
	  || (echo "LAYER VIOLATION: a backend, upscaler or ZephraMedia is imported outside ZephraApp.swift"; exit 1)
# The phone links the value layer, the wire and the chrome, and nothing else. It has no engine
# of its own, no folder on disk and no backend: everything it shows came over the link from a
# Mac. AppKit is in the list because it would compile on nothing and mean the file was written
# for the wrong app.
	@! grep -rlnE '^import (ZephraBackend|ZephraUpscale|ZephraMedia|ZephraSnapshot|ZephraEngine|AppKit)' Sources/ZephraMobile --include='*.swift' 2>/dev/null \
	  || (echo "LAYER VIOLATION: the phone imports something only the Mac may have (see AGENTS.md, The phone)"; exit 1)
	@! grep -rlnE '^import (ZImage|QwenImage|Flux2|LTX2|Wan|MLX)' Packages/ZephraKit/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: ZephraKit imports a model package or MLX"; exit 1)
	@! grep -rlnE '^import (ZephraBackend|ZephraUpscale)' Packages/ZephraBackend*/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: one backend package imports another, or the upscaler"; exit 1)
	@! grep -rlnE '^import (ZImage|QwenImage|Flux2|LTX2|Wan|ZephraBackend)' Packages/ZephraUpscale*/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: an upscaler package imports a model family"; exit 1)
	@status=0; for family in $(FAMILIES); do \
	  others=$$(echo "$(FAMILIES)" | tr ' ' '\n' | grep -v "^$$family$$" | paste -sd'|' -); \
	  if grep -rlnE "^import ($$others)$$" Packages/ZephraBackend$$family/Sources 2>/dev/null; then \
	    echo "LAYER VIOLATION: ZephraBackend$$family imports another family's kit"; status=1; \
	  fi; \
	done; exit $$status
	@! grep -rlnE '^import (ZImage|QwenImage|Flux2|LTX2|Wan|ZephraBackend|ZephraUpscale)' Packages/ZephraMLXKit/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: ZephraMLXKit imports a model package; nothing there may depend on a family"; exit 1)
	@! grep -rlnE '^import (SwiftUI|AppKit|UIKit)' Packages/ZephraKit/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: UI framework imported inside ZephraKit"; exit 1)
# The chrome is drawn by both apps, so it may name SwiftUI and ZephraCore and nothing else:
# a platform's own toolkit or the engine's state would make it one app's again. The one
# platform difference, the hairline's separator colour, is spelled with #if os(macOS).
	@! grep -rlnE '^import (AppKit|UIKit|ZephraEngine)' Packages/ZephraStyle/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: ZephraStyle imports AppKit, UIKit or ZephraEngine; the chrome is drawn on both platforms"; exit 1)
# ZephraLink is the one package an iOS app links too, so what it may import is a short
# list rather than a short ban: Foundation-level frameworks, the two ZephraKit modules
# that hold the on-disk truth, and itself. Anything else -- a backend, MLX, a UI
# framework, ZephraSnapshot -- would make the protocol Mac-only.
	@! grep -rhnE '^import ' Packages/ZephraLink/Sources 2>/dev/null \
	  | grep -vE '^[0-9]+:import (Foundation|CryptoKit|Network|os|Observation|ImageIO|CoreGraphics|Synchronization|ZephraCore|ZephraEngine|ZephraLink[A-Za-z]*)$$' \
	  || (echo "LAYER VIOLATION: ZephraLink imports something an iOS app cannot link (see AGENTS.md)"; exit 1)
	@! grep -rlnE 'repeatForever|repeatCount\(|TimelineView\(\.animation|phaseAnimator|keyframeAnimator' Sources/Zephra Sources/ZephraMobile --include='*.swift' \
	  || (echo "ANIMATION VIOLATION: an app target runs a repeating animation; the GPU is the model's while it works (see RunPlaceholderView)"; exit 1)
	@! grep -rlnE 'hoverWash' Sources/Zephra --include='*.swift' | grep -vE 'WallSquareChrome\.swift|ZephraChrome\+Washes\.swift' \
	  || (echo "HIT-TEST VIOLATION: the hover wash is laid over a button outside WallSquareChrome, where allowsHitTesting(false) keeps it from taking the click"; exit 1)
# US spelling in user-facing strings, which AGENTS.md asks for and six shipped literals
# had drifted from -- "6 favourites" under a sidebar row reading Favorites among them.
# Whole lines, not `grep -o`: the match alone loses the context that tells a doc comment
# from code, and every remaining occurrence in the tree is in a comment. Identifiers are
# exempt on purpose (isFavourite, FavouriteToggle) since no user sees them, and so is
# LibraryScope, whose "favourites" is the stable spelling written into preferences --
# changing that one would orphan every saved scope.
	@! grep -rnE '"[^"]*([Ff]avourite|[Cc]olour|[Cc]entre|[Bb]ehaviour|[Ll]icence|[Oo]rganise|[Aa]nalyse|[Nn]ormalise|[Cc]ancelled)[^"]*"' \
	  Sources/Zephra Sources/ZephraMobile Packages/ZephraKit/Sources Packages/ZephraMLXKit/Sources \
	  Packages/ZephraStyle/Sources Packages/ZephraLink/Sources --include='*.swift' 2>/dev/null \
	  | grep -vE ':[0-9]+: *(///|//|\*)' | grep -v '#Preview' | grep -v 'LibraryScope\.swift' \
	  || (echo "SPELLING VIOLATION: a user-facing string is in British spelling; AGENTS.md asks for US spelling on screen (identifiers are exempt)"; exit 1)
# The type-name ban from AGENTS.md's code rules. PromptLayoutManager is the one documented
# exception: it is an NSLayoutManager subclass and keeps AppKit's own name.
	@! grep -rnE '(struct|class|enum|actor|protocol) [A-Za-z]*(Manager|Helper|Utils|Utility|Service)\b' \
	  Sources Packages --include='*.swift' 2>/dev/null \
	  | grep -v 'Packages/ZImageKit' | grep -v 'PromptLayoutManager' \
	  || (echo "NAMING VIOLATION: name a type for what it is, not Manager/Helper/Utils/Service (AGENTS.md)"; exit 1)
	@echo "layers ok"

# Advisory, never a gate: the 150-line figure in AGENTS.md is a target to split before,
# not a limit to fail on, and a file a few lines over is usually carrying a comment that
# earns its place. Printed so the drift stays visible.
#
# The three-stored-properties-per-view rule is deliberately NOT linted. It cannot be
# checked honestly by grep -- telling a stored property from a computed one or from a
# local inside a function needs the parser, and every regex tried for it flagged
# CacheLimitControl's `bounds`, PromptTuckOverlay's `tucked` and LibraryGridKeyboard's
# `outcome`, none of which are stored. A rule that cries wolf is worse than one a
# reviewer applies by eye.
lint-size:
	@find Sources Packages -name '*.swift' | grep -v ZImageKit | grep -v '/Tests/' \
	  | grep -v '\.build' | xargs wc -l 2>/dev/null | sort -rn \
	  | awk '$$1 > 150 && $$2 != "total" { print "  over 150 lines: " $$1 "\t" $$2 }'
	@echo "size advisory done"

# ChatGPT Sites is the iteration environment; production means the AWS website.
WEBSITE_PROFILE      ?= dev.urandom.io
WEBSITE_BUCKET       ?= zephra-site-urandom-io
WEBSITE_DISTRIBUTION ?= ETNI7JSPHMJRF
WEBSITE_URL          ?= https://zephra.urandom.io
.PHONY: website-build deploy-production
# `npm ci` first when the tree is not there, because this runs at the end of `make ship`, after
# twenty minutes of notarization and after the release is already public. A missing
# `node_modules` failed the whole target with "vinext: command not found" at exactly that point,
# leaving the DMG published and the website still naming the build before it. `ci` rather than
# `install`, so the lockfile decides and a ship never quietly moves a dependency.
website-build:
	@if [ ! -d product-mockups/node_modules ]; then \
	  echo "website-build: installing product-mockups dependencies"; \
	  cd product-mockups && npm ci; \
	fi
	cd product-mockups && ZEPHRA_STATIC_EXPORT=1 npm run build

deploy-production: website-build
	WEBSITE_PROFILE="$(WEBSITE_PROFILE)" WEBSITE_BUCKET="$(WEBSITE_BUCKET)" \
	WEBSITE_DISTRIBUTION="$(WEBSITE_DISTRIBUTION)" WEBSITE_URL="$(WEBSITE_URL)" \
	./scripts/deploy-website.sh

# macOS-only: validates notarization before upload, then verifies the public download.
RELEASE_PROFILE ?= dev.urandom.io
# What `publish-download.sh` rewrites with the URL, version, build and SHA-256 of the upload,
# and what the website's Download button reads. The one file a ship changes in the repo.
RELEASE_MANIFEST := product-mockups/app/release.json
# The distribution in front of the assets bucket, so the ship can forget the cached copy of the
# one key it mutates (`releases/Zephra-latest.dmg`). The same distribution the mirror uses --
# releases and models are prefixes of one bucket behind one host.
RELEASE_DISTRIBUTION ?= $(MIRROR_DISTRIBUTION)
.PHONY: release-upload publish-release
release-upload:
	RELEASE_PROFILE="$(RELEASE_PROFILE)" RELEASE_DISTRIBUTION="$(RELEASE_DISTRIBUTION)" \
	  ./scripts/publish-download.sh

publish-release: notarized-release
	$(MAKE) release-upload

# The whole pre-release ship, as it is done until further notice: the version stays at
# project.yml's 0.1.0 and the build number is the UTC minute the build started
# (YYYYMMDDHHMM), which is unique, sorts, and reads as a date; then the site is redeployed so
# its Download button names the new file, and the manifest that says which file that is
# is committed and pushed, because a shipped release whose manifest sits dirty in a working
# copy is a release nobody else can reproduce. See "Build & run" in AGENTS.md.
#
# Old releases are deliberately NOT cleaned up here. They are removed by hand now and then
# (`aws --profile $(RELEASE_PROFILE) s3 rm s3://.../releases/<file>`); the bucket has no
# versioning, so a delete is permanent and does not belong in an automated path.
RELEASE_STAMP := $(shell date -u +%Y%m%d%H%M)
.PHONY: ship release-commit
ship:
	$(MAKE) publish-release VERSION=0.1.0 BUILD_NUMBER=$(RELEASE_STAMP)
	$(MAKE) deploy-production
	$(MAKE) release-commit

# Commits and pushes the one file the ship rewrote. Only that path is staged, so whatever else
# is in the working copy is left alone and never rides along in a release commit. The stamp in
# the message is read back out of the manifest rather than from RELEASE_STAMP, so it names the
# build that was actually uploaded even if the ship crossed a minute boundary.
release-commit:
	@if git diff --quiet -- "$(RELEASE_MANIFEST)"; then \
	  echo "release-commit: $(RELEASE_MANIFEST) is unchanged, nothing to commit"; \
	  exit 0; \
	fi; \
	stamp=$$(python3 -c 'import json;print(json.load(open("$(RELEASE_MANIFEST)"))["build"])'); \
	branch=$$(git rev-parse --abbrev-ref HEAD); \
	git add "$(RELEASE_MANIFEST)" && \
	git commit -m "chore(release): publish Zephra-0.1.0-$$stamp" && \
	git push origin "$$branch" && \
	echo "release-commit: pushed $$branch"
