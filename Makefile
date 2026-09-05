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
# One download directory per repository, named as the app names it: <org>--<repo>.
ZIMAGE_8BIT_DIR := $(DOWNLOADS)/$(subst /,--,$(MODEL))
ZIMAGE_BASE_DIR := $(DOWNLOADS)/$(subst /,--,$(BASE_MODEL))
FLUX2_DIR       := $(DOWNLOADS)/$(subst /,--,$(FLUX2_MODEL))

DEST     := platform=macOS,arch=arm64
XCB      := xcodebuild -project "$(PROJECT)" -destination '$(DEST)' SYMROOT="$(BUILD)" -derivedDataPath "$(DERIVED)"
# Every package that links MLX, and so needs xcodebuild rather than `swift test`, written as
# directory:scheme. SwiftPM names a package's scheme after the package, except where it ships
# more than one library product, when the aggregate that covers every test target is
# <name>-Package. Only ZephraMLXKit does, because a model package takes ZephraMLX without
# dragging in the quantizer.
MLX_PACKAGES := ZephraMLXKit:ZephraMLXKit-Package QwenImageKit:QwenImageKit ZephraUpscaleRealESRGAN:ZephraUpscaleRealESRGAN \
                Flux2Kit:Flux2Kit \
                ZephraBackendZImage:ZephraBackendZImage \
                ZephraBackendQwenImage:ZephraBackendQwenImage \
                ZephraBackendFlux2:ZephraBackendFlux2

# Distribution signing. The build itself is ad-hoc signed (project.yml), so these
# matter only to `make release` and `make notarize`. Leave SIGN_IDENTITY empty to
# take the first "Developer ID Application" identity in the keychain.
SIGN_IDENTITY  ?=
NOTARY_PROFILE ?= zephra-notary
SIGNING_CONFIG ?= $(HOME)/Documents/Zephra Signing/signing.env
RELEASE_APP    := $(BUILD)/Release/Zephra.app
RELEASE_ZIP    := $(BUILD)/Zephra.zip
RELEASE_DMG    := $(BUILD)/Zephra.dmg

.PHONY: doctor gen build run bench quantize quantize-qwen quantize-flux2 prefetch prefetch-qwen prefetch-flux2 open clean lint-layers logs screenshot test test-app test-mlx test-backend icon signed-build release notarize notarized-release

# What a fresh Mac needs before `make build` can work, each with its fix printed.
doctor:
	@scripts/doctor.sh

gen:
	xcodegen generate --spec project.yml

build: gen
	$(XCB) -scheme $(SCHEME) -configuration $(CONFIG) build

run: build
	open -a "$(APP)"

bench: gen
	@mkdir -p "$(BUILD)"; $(XCB) -scheme ZephraBench -configuration Release build >"$(BUILD)/ZephraBench-build.log" 2>&1 \
	  || { tail -40 "$(BUILD)/ZephraBench-build.log"; echo "ZephraBench failed to build; full log in $(BUILD)/ZephraBench-build.log"; exit 1; }
	$(BENCH) $(ARGS)

# Build the 4-bit variant locally: no repository publishes Z-Image-Turbo in the manifest format
# the vendored loader reads. The download is the slow part; the quantization itself is a minute.
quantize: gen
	@mkdir -p "$(BUILD)"; $(XCB) -scheme ZephraQuantize -configuration Release build >"$(BUILD)/ZephraQuantize-build.log" 2>&1 \
	  || { tail -40 "$(BUILD)/ZephraQuantize-build.log"; echo "ZephraQuantize failed to build; full log in $(BUILD)/ZephraQuantize-build.log"; exit 1; }
	@set -e; source=$$(hf download $(BASE_MODEL) --exclude 'assets/*' --local-dir "$(ZIMAGE_BASE_DIR)"); \
	"$(QUANTIZE)" --family z-image \
	  --source "$$source" \
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
	if [ -z "$$source" ]; then source=$$(hf download $(FLUX2_MODEL) $(FLUX2_EXCLUDE) --local-dir "$(FLUX2_DIR)"); fi; \
	"$(QUANTIZE)" --family flux2 \
	  --source "$$source" \
	  --source-name $(FLUX2_MODEL) --bits $(BITS) --group-size $(GROUP_SIZE) \
	  --out "$(FLUX2_OUT)" $(ARGS)

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
# `make test` on purpose: that one stays MLX-free and fast.
test-mlx:
	@for entry in $(MLX_PACKAGES); do \
	  package=$${entry%%:*}; scheme=$${entry##*:}; \
	  echo "== $$package"; \
	  ( cd $(CURDIR)/Packages/$$package && xcodebuild test -scheme $$scheme \
	    -destination 'platform=macOS' -skipPackagePluginValidation \
	    -derivedDataPath $(DERIVED) ) || exit 1; \
	done

# The name this had when there was one such package.
test-backend: test-mlx

icon:
	swift scripts/make-icon.swift

# Build and sign the app for distribution. If present, SIGNING_CONFIG is sourced
# before signing so a local machine can keep its identity selection in Documents.
signed-build:
	$(MAKE) CONFIG=Release build
	@set -a; \
	if [ -f "$(SIGNING_CONFIG)" ]; then . "$(SIGNING_CONFIG)"; fi; \
	set +a; \
	if [ -n "$(SIGN_IDENTITY)" ]; then SIGN_IDENTITY="$(SIGN_IDENTITY)"; fi; \
	export SIGN_IDENTITY; \
	./scripts/sign-release.sh "$(RELEASE_APP)"

# Package the signed app as a ZIP and a signed DMG. Notarization is separate;
# distribution signatures use Apple secure timestamps.
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

# Layering rules from CLAUDE.md, enforced mechanically. The patterns are deliberately
# family-agnostic: a second backend package must not need a Makefile edit to be policed.
lint-layers:
	@! grep -rlnE '^import (ZImage|QwenImage|Flux2|MLX)' Sources/Zephra Sources/ZephraBench Sources/ZephraQuantize --include='*.swift' \
	  || (echo "LAYER VIOLATION: app or tool target imports a model package or MLX directly"; exit 1)
	@! grep -rlnE '^import (ZephraBackend|ZephraUpscale)' Sources/Zephra --include='*.swift' | grep -v 'ZephraApp.swift' \
	  || (echo "LAYER VIOLATION: a backend or upscaler package is imported outside ZephraApp.swift"; exit 1)
	@! grep -rlnE '^import (ZImage|QwenImage|Flux2|MLX)' Packages/ZephraKit/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: ZephraKit imports a model package or MLX"; exit 1)
	@! grep -rlnE '^import (ZephraBackend|ZephraUpscale)' Packages/ZephraBackend*/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: one backend package imports another, or the upscaler"; exit 1)
	@! grep -rlnE '^import (ZImage|QwenImage|Flux2|ZephraBackend)' Packages/ZephraUpscale*/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: an upscaler package imports a model family"; exit 1)
	@status=0; for family in ZImage QwenImage Flux2; do \
	  others=$$(echo "ZImage QwenImage Flux2" | tr ' ' '\n' | grep -v "^$$family$$" | paste -sd'|' -); \
	  if grep -rlnE "^import ($$others)$$" Packages/ZephraBackend$$family/Sources 2>/dev/null; then \
	    echo "LAYER VIOLATION: ZephraBackend$$family imports another family's kit"; status=1; \
	  fi; \
	done; exit $$status
	@! grep -rlnE '^import (ZImage|QwenImage|Flux2|ZephraBackend|ZephraUpscale)' Packages/ZephraMLXKit/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: ZephraMLXKit imports a model package; nothing there may depend on a family"; exit 1)
	@! grep -rlnE '^import (SwiftUI|AppKit)' Packages/ZephraKit/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: UI framework imported inside ZephraKit"; exit 1)
	@! grep -rlnE 'repeatForever|repeatCount\(|TimelineView\(\.animation|phaseAnimator|keyframeAnimator' Sources/Zephra --include='*.swift' \
	  || (echo "ANIMATION VIOLATION: the app target runs a repeating animation; the GPU is the model's while it works (see RunPlaceholderView)"; exit 1)
	@echo "layers ok"
