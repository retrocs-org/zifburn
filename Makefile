APP      := ZIFburn
BUILD    := build
BUNDLE   := $(BUILD)/$(APP).app
CONFIG   ?= release
PYTHON   ?= python3
SIGN_IDENTITY ?= -
SIGN_FLAGS ?=
VERSION  := $(shell cat VERSION)
DIST     := zifburn-$(VERSION)

.PHONY: all build app run dev install universal dist icon test clean

all: app

build:
	swift build -c $(CONFIG)

app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/$(APP)" "$(BUNDLE)/Contents/MacOS/$(APP)"
	cp Support/Info.plist "$(BUNDLE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(BUNDLE)/Contents/Info.plist"
	cp Support/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	cp LICENSE "$(BUNDLE)/Contents/Resources/LICENSE"
	/usr/libexec/PlistBuddy -c "Add :ZIFburnBuild string $$(date +%Y%m%d.%H%M)" "$(BUNDLE)/Contents/Info.plist"
	codesign --force $(SIGN_FLAGS) --sign "$(SIGN_IDENTITY)" "$(BUNDLE)"
	@echo "Built $(BUNDLE) ($$(/usr/libexec/PlistBuddy -c 'Print :ZIFburnBuild' "$(BUNDLE)/Contents/Info.plist"))"

universal:
	swift build -c release --arch arm64 --arch x86_64
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$(APP)" "$(BUNDLE)/Contents/MacOS/$(APP)"
	cp Support/Info.plist "$(BUNDLE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(BUNDLE)/Contents/Info.plist"
	cp Support/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	cp LICENSE "$(BUNDLE)/Contents/Resources/LICENSE"
	/usr/libexec/PlistBuddy -c "Add :ZIFburnBuild string $$(date +%Y%m%d.%H%M)" "$(BUNDLE)/Contents/Info.plist"
	codesign --force $(SIGN_FLAGS) --sign "$(SIGN_IDENTITY)" "$(BUNDLE)"

run: app
	-@osascript -e 'if application "ZIFburn" is running then tell application "ZIFburn" to quit' 2>/dev/null; sleep 1
	open "$(BUNDLE)"

test:
	swift test

dev:
	swift run $(APP)

install: app
	rm -rf "/Applications/$(APP).app"
	cp -R "$(BUNDLE)" /Applications/

dist:
	"$(PYTHON)" scripts/source_release.py

# Regenerate Support/AppIcon.icns from the 1024px master with macOS's own
# tools (sips + iconutil). Edit Support/Icon/AppIcon.svg, export it to
# Support/Icon/AppIcon-1024.png, then run `make icon`.
icon:
	rm -rf "$(BUILD)/AppIcon.iconset" && mkdir -p "$(BUILD)/AppIcon.iconset"
	@for s in 16 32 128 256 512; do \
	    sips -z $$s $$s Support/Icon/AppIcon-1024.png --out "$(BUILD)/AppIcon.iconset/icon_$${s}x$${s}.png" >/dev/null; \
	    d=$$((s*2)); \
	    sips -z $$d $$d Support/Icon/AppIcon-1024.png --out "$(BUILD)/AppIcon.iconset/icon_$${s}x$${s}@2x.png" >/dev/null; \
	done
	iconutil -c icns "$(BUILD)/AppIcon.iconset" -o Support/AppIcon.icns
	@echo "Updated Support/AppIcon.icns"

clean:
	rm -rf .build $(BUILD)

# Developer ID signing and notarization; credentials stay in the keychain.
.PHONY: release website-check
release:
	"$(PYTHON)" scripts/release.py build

website-check:
	"$(PYTHON)" scripts/check_web.py

.PHONY: website-preview website-package
website-preview:
	php -S localhost:8080 -t public-web

website-package: website-check
	mkdir -p "$(BUILD)"
	COPYFILE_DISABLE=1 tar --exclude=.DS_Store --exclude='._*' -czf "$(BUILD)/zifburn-website.tar.gz" -C public-web index.php get.php release-data.php content.php style.css LICENSE assets

.PHONY: release-plan release-check release-prepare release-tests
release-plan:
	"$(PYTHON)" scripts/release.py plan

release-check:
	"$(PYTHON)" scripts/release.py check

release-prepare:
	"$(PYTHON)" scripts/release.py prepare

release-tests:
	"$(PYTHON)" -B -m unittest discover -s Tests/ReleaseTools -b
