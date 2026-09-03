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

# `make quantize` builds the 4-bit variant from the full-precision release. BITS and GROUP_SIZE
# pick the trade-off; QUANT_OUT must match ModelCatalog.zImageTurbo4bit's local directory.
BASE_MODEL := Tongyi-MAI/Z-Image-Turbo
BITS       ?= 4
GROUP_SIZE ?= 64
QUANT_OUT  ?= $(HOME)/Library/Application Support/Zephra/Models/z-image-turbo-4bit

# Qwen-Image-2512 is 57.7 GB in bf16, too large for the boot volume here, so its full-precision
# source and its distillation adapter live on external storage. Point QWEN_SOURCE and QWEN_LORA
# wherever they are on this machine; `make prefetch-qwen` puts them there.
QWEN_MODEL  := Qwen/Qwen-Image-2512
QWEN_LORA_REPO := lightx2v/Qwen-Image-2512-Lightning
# The four-step adapter in float32. The repository also ships whole merged checkpoints of twenty
# gigabytes each, which is why this names one file rather than downloading the repository.
QWEN_LORA_FILE := Qwen-Image-2512-Lightning-4steps-V1.0-fp32.safetensors
QWEN_MODELS ?= /Volumes/ExternalStorage/Models
QWEN_SOURCE ?= $(QWEN_MODELS)/Qwen-Image-2512
QWEN_LORA   ?= $(QWEN_MODELS)/Qwen-Image-2512-Lightning/$(QWEN_LORA_FILE)
QWEN_OUT    ?= $(HOME)/Library/Application Support/Zephra/Models/qwen-image-2512-4bit
DEST     := platform=macOS,arch=arm64
XCB      := xcodebuild -project $(PROJECT) -destination '$(DEST)' SYMROOT=$(BUILD) -derivedDataPath $(DERIVED)
# Every package that links MLX, and so needs xcodebuild rather than `swift test`, written as
# directory:scheme. SwiftPM names a package's scheme after the package, except where it ships
# more than one library product, when the aggregate that covers every test target is
# <name>-Package. Only ZephraMLXKit does, because a model package takes ZephraMLX without
# dragging in the quantizer.
MLX_PACKAGES := ZephraMLXKit:ZephraMLXKit-Package QwenImageKit:QwenImageKit \
                ZephraBackendZImage:ZephraBackendZImage \
                ZephraBackendQwenImage:ZephraBackendQwenImage

# Distribution signing. The build itself is ad-hoc signed (project.yml), so these
# matter only to `make release` and `make notarize`. Leave SIGN_IDENTITY empty to
# take the first "Developer ID Application" identity in the keychain.
SIGN_IDENTITY  ?=
NOTARY_PROFILE ?= zephra-notary
RELEASE_APP    := $(BUILD)/Release/Zephra.app
RELEASE_ZIP    := $(BUILD)/Zephra.zip

.PHONY: doctor gen build run bench quantize quantize-qwen prefetch prefetch-qwen open clean lint-layers logs screenshot test test-mlx test-backend icon release notarize

# What a fresh Mac needs before `make build` can work, each with its fix printed.
doctor:
	@scripts/doctor.sh

gen:
	xcodegen generate --spec project.yml

build: gen
	$(XCB) -scheme $(SCHEME) -configuration $(CONFIG) build

run: build
	open -a $(APP)

bench: gen
	$(XCB) -scheme ZephraBench -configuration Release build >/dev/null
	$(BENCH) $(ARGS)

# Build the 4-bit variant locally: no repository publishes Z-Image-Turbo in the manifest format
# the vendored loader reads. The download is the slow part; the quantization itself is a minute.
quantize: gen
	$(XCB) -scheme ZephraQuantize -configuration Release build >/dev/null
	"$(QUANTIZE)" --family z-image \
	  --source "$$(hf download $(BASE_MODEL) --exclude 'assets/*')" \
	  --source-name $(BASE_MODEL) --bits $(BITS) --group-size $(GROUP_SIZE) \
	  --out "$(QUANT_OUT)" $(ARGS)

# The Qwen build merges the four-step Lightning adapter into the transformer as it packs, so what
# lands in QWEN_OUT is the distilled model and the runtime never sees an adapter. The base model
# wants fifty steps and real guidance, which is two passes through twenty billion parameters per
# step; without the merge this build is unusable rather than merely slower.
quantize-qwen: gen
	$(XCB) -scheme ZephraQuantize -configuration Release build >/dev/null
	"$(QUANTIZE)" --family qwen-image \
	  --source "$(QWEN_SOURCE)" --lora "$(QWEN_LORA)" \
	  --source-name $(QWEN_MODEL) --bits $(BITS) --group-size $(GROUP_SIZE) \
	  --out "$(QWEN_OUT)" $(ARGS)

test:
	cd Packages/ZephraKit && swift test

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

# Build, sign for distribution, verify, and package. No network: notarization is
# a separate step so this one works offline.
release:
	$(MAKE) CONFIG=Release build
	SIGN_IDENTITY='$(SIGN_IDENTITY)' ./scripts/sign-release.sh $(RELEASE_APP)
	rm -f $(RELEASE_ZIP)
	ditto -c -k --keepParent $(RELEASE_APP) $(RELEASE_ZIP)
	@echo "release: $(RELEASE_ZIP) is signed and ready for 'make notarize'"

# Submit to Apple, staple the ticket, repackage. Needs credentials stored once:
#   xcrun notarytool store-credentials $(NOTARY_PROFILE) \
#       --apple-id <apple id> --team-id <team id> --password <app-specific password>
notarize:
	NOTARY_PROFILE='$(NOTARY_PROFILE)' ./scripts/notarize-release.sh $(RELEASE_APP) $(RELEASE_ZIP)

prefetch:
	hf download $(MODEL) --exclude "assets/*"

# Qwen-Image-2512 and its four-step adapter, onto QWEN_MODELS rather than into the hub cache:
# 57.7 GB does not belong on a boot volume, and the loader reads a plain directory anyway.
prefetch-qwen:
	hf download $(QWEN_MODEL) --local-dir "$(QWEN_SOURCE)"
	hf download $(QWEN_LORA_REPO) $(QWEN_LORA_FILE) \
	  --local-dir "$(QWEN_MODELS)/Qwen-Image-2512-Lightning"

open: gen
	open $(PROJECT)

clean:
	rm -rf $(BUILD) $(DERIVED) $(PROJECT)

logs:
	log stream --style compact --predicate 'subsystem == "io.zephra"'

screenshot:
	./scripts/screenshot.sh

# Layering rules from CLAUDE.md, enforced mechanically. The patterns are deliberately
# family-agnostic: a second backend package must not need a Makefile edit to be policed.
lint-layers:
	@! grep -rlnE '^import (ZImage|QwenImage|MLX)' Sources/Zephra Sources/ZephraBench Sources/ZephraQuantize --include='*.swift' \
	  || (echo "LAYER VIOLATION: app or tool target imports a model package or MLX directly"; exit 1)
	@! grep -rlnE '^import ZephraBackend' Sources/Zephra --include='*.swift' | grep -v 'ZephraApp.swift' \
	  || (echo "LAYER VIOLATION: a backend package is imported outside ZephraApp.swift"; exit 1)
	@! grep -rlnE '^import (ZImage|QwenImage|MLX)' Packages/ZephraKit/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: ZephraKit imports a model package or MLX"; exit 1)
	@! grep -rlnE '^import ZephraBackend' Packages/ZephraBackend*/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: one backend package imports another"; exit 1)
	@! grep -rlnE '^import (SwiftUI|AppKit)' Packages/ZephraKit/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: UI framework imported inside ZephraKit"; exit 1)
	@echo "layers ok"
