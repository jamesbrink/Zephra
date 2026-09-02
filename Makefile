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
DEST     := platform=macOS,arch=arm64
XCB      := xcodebuild -project $(PROJECT) -destination '$(DEST)' SYMROOT=$(BUILD) -derivedDataPath $(DERIVED)
BACKEND  := $(CURDIR)/Packages/ZephraBackendZImage

# Distribution signing. The build itself is ad-hoc signed (project.yml), so these
# matter only to `make release` and `make notarize`. Leave SIGN_IDENTITY empty to
# take the first "Developer ID Application" identity in the keychain.
SIGN_IDENTITY  ?=
NOTARY_PROFILE ?= zephra-notary
RELEASE_APP    := $(BUILD)/Release/Zephra.app
RELEASE_ZIP    := $(BUILD)/Zephra.zip

.PHONY: gen build run bench quantize prefetch open clean lint-layers logs screenshot test test-backend icon release notarize

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
# the vendored loader reads. The download is the slow part; the quantization itself is minutes.
quantize: gen
	$(XCB) -scheme ZephraQuantize -configuration Release build >/dev/null
	"$(QUANTIZE)" --source "$$(hf download $(BASE_MODEL) --exclude 'assets/*')" \
	  --source-name $(BASE_MODEL) --bits $(BITS) --group-size $(GROUP_SIZE) \
	  --out "$(QUANT_OUT)" $(ARGS)

test:
	cd Packages/ZephraKit && swift test

# The backend links MLX, so its tests need xcodebuild rather than `swift test`.
# Kept out of `make test` on purpose: that one stays MLX-free and fast.
test-backend:
	cd $(BACKEND) && xcodebuild test -scheme ZephraBackendZImage \
	  -destination 'platform=macOS' -skipPackagePluginValidation \
	  -derivedDataPath $(DERIVED)

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
