# Zephra build entry points. The Xcode project is generated (gitignored); never edit it by hand.
SCHEME   := Zephra
PROJECT  := Zephra.xcodeproj
CONFIG   ?= Release
BUILD    := $(CURDIR)/build
DERIVED  := $(CURDIR)/.build/DerivedData
APP      := $(BUILD)/$(CONFIG)/Zephra.app
BENCH    := $(BUILD)/Release/ZephraBench
MODEL    := mzbac/Z-Image-Turbo-8bit
DEST     := platform=macOS,arch=arm64
XCB      := xcodebuild -project $(PROJECT) -destination '$(DEST)' SYMROOT=$(BUILD) -derivedDataPath $(DERIVED)
BACKEND  := $(CURDIR)/Packages/ZephraBackendZImage

.PHONY: gen build run bench prefetch open clean lint-layers logs screenshot test test-backend

gen:
	xcodegen generate --spec project.yml

build: gen
	$(XCB) -scheme $(SCHEME) -configuration $(CONFIG) build

run: build
	open -a $(APP)

bench: gen
	$(XCB) -scheme ZephraBench -configuration Release build >/dev/null
	$(BENCH) $(ARGS)

test:
	cd Packages/ZephraKit && swift test

# The backend links MLX, so its tests need xcodebuild rather than `swift test`.
# Kept out of `make test` on purpose: that one stays MLX-free and fast.
test-backend:
	cd $(BACKEND) && xcodebuild test -scheme ZephraBackendZImage \
	  -destination 'platform=macOS' -skipPackagePluginValidation \
	  -derivedDataPath $(DERIVED)

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

# Layering rules from CLAUDE.md, enforced mechanically.
lint-layers:
	@! grep -rln '^import ZImage\|^import MLX' Sources/Zephra Sources/ZephraBench --include='*.swift' \
	  || (echo "LAYER VIOLATION: app or bench target imports ZImage or MLX directly"; exit 1)
	@! grep -rln '^import ZephraBackendZImage' Sources/Zephra --include='*.swift' | grep -v 'ZephraApp.swift' \
	  || (echo "LAYER VIOLATION: ZephraBackendZImage imported outside ZephraApp.swift"; exit 1)
	@! grep -rln '^import ZImage\|^import MLX' Packages/ZephraKit/Sources/ZephraCore Packages/ZephraKit/Sources/ZephraEngine 2>/dev/null \
	  || (echo "LAYER VIOLATION: ZephraCore/ZephraEngine import ZImage or MLX"; exit 1)
	@! grep -rln '^import SwiftUI\|^import AppKit' Packages/ZephraKit/Sources 2>/dev/null \
	  || (echo "LAYER VIOLATION: UI framework imported inside ZephraKit"; exit 1)
	@echo "layers ok"
