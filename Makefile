APP_NAME := neowall
APP := build/$(APP_NAME).app
PLIST := Resources/Info.plist
ICON := Resources/AppIcon.icns
DMG := $(APP_NAME).dmg

# `make app` builds for this Mac only, which is what development wants. `make release`
# builds one binary for Apple Silicon and Intel, so there is a single download.
ifdef UNIVERSAL
ARCH_FLAGS := --arch arm64 --arch x86_64
endif
# Asked of SwiftPM rather than hard-coded: the products of a universal build land in a
# different directory, and which one depends on the toolchain.
BIN_DIR = $(shell swift build -c release $(ARCH_FLAGS) --show-bin-path 2>/dev/null)

# Signing identity, in order of preference: Developer ID Application (the only one other
# Macs accept and Apple notarizes), Apple Development, then ad-hoc. Revoked certificates
# are still listed by `find-identity -v`, so they are filtered out.
# Override with `make SIGN_IDENTITY=-` to force ad-hoc.
IDENTITIES = security find-identity -v -p codesigning 2>/dev/null | grep -v CSSMERR_TP_CERT_REVOKED
SIGN_IDENTITY ?= $(shell $(IDENTITIES) | grep -m1 -o '"Developer ID Application: [^"]*"' | tr -d '"')
ifeq ($(strip $(SIGN_IDENTITY)),)
SIGN_IDENTITY := $(shell $(IDENTITIES) | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"')
endif
ifeq ($(strip $(SIGN_IDENTITY)),)
SIGN_IDENTITY := -
endif

# Hardened runtime and a secure timestamp, both required for notarization. Skipped for
# ad-hoc: the timestamp needs Apple's server and an ad-hoc build is never notarized.
ifeq ($(SIGN_IDENTITY),-)
CODESIGN_FLAGS :=
else
CODESIGN_FLAGS := --options runtime --timestamp
endif
CODESIGN = codesign --force $(CODESIGN_FLAGS) --sign "$(SIGN_IDENTITY)"

.PHONY: build app run install test clean release dmg check-devid notarize-app notarize-dmg

build:
	swift build -c release $(ARCH_FLAGS)

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources $(APP)/Contents/Frameworks
	cp $(BIN_DIR)/$(APP_NAME) $(APP)/Contents/MacOS/$(APP_NAME)
	cp $(PLIST) $(APP)/Contents/Info.plist
	cp $(ICON) $(APP)/Contents/Resources/AppIcon.icns
	# swift build links against Sparkle.framework but does not copy it into the bundle.
	# `cp -R` keeps the framework's Versions/ symlinks and the executable bits of its XPC
	# services; flattening them is the usual reason Sparkle will not start.
	install_name_tool -add_rpath @executable_path/../Frameworks $(APP)/Contents/MacOS/$(APP_NAME)
	cp -R $(BIN_DIR)/Sparkle.framework $(APP)/Contents/Frameworks/
	xattr -cr $(APP)
	# Signed inside out, each piece on its own. Not `--deep`: it re-signs nested code with
	# the outer bundle's options, and notarization rejects the result.
	@set -e; SPK=$(APP)/Contents/Frameworks/Sparkle.framework/Versions/B; \
	for code in "$$SPK"/XPCServices/*.xpc "$$SPK/Updater.app" "$$SPK/Autoupdate" "$$SPK"; do \
	  $(CODESIGN) "$$code"; \
	done
	$(CODESIGN) $(APP)
	codesign --verify --deep --strict $(APP)

run: app
	open $(APP)

install: app
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/$(APP_NAME).app

test:
	swift test

clean:
	rm -rf .build build $(DMG)

# ── Distribution ──────────────────────────────────────────────────────────────
# scripts/release.sh drives these targets in order; see docs/RELEASING.md.

release:
	$(MAKE) app UNIVERSAL=1

# Refuses to submit something Apple will reject minutes later.
check-devid:
	@case "$(SIGN_IDENTITY)" in \
	  "Developer ID Application"*) ;; \
	  *) echo "ERROR: notarization requires a Developer ID Application identity."; \
	     echo "       Current SIGN_IDENTITY: $(SIGN_IDENTITY)"; exit 1 ;; \
	esac

# NOTARY_PROFILE names a Keychain item shared with the sibling apps, created once with:
#   xcrun notarytool store-credentials vaho-notary --apple-id <apple-id> --team-id <team-id>
NOTARY_PROFILE ?= vaho-notary
NOTARIZE_ZIP := build/notarize-upload.zip

# Stapled before the app is zipped for Sparkle or copied into the disk image, so both
# carry the ticket and a first launch works offline.
notarize-app: check-devid
	@test -d $(APP) || { echo "ERROR: $(APP) not found — run 'make release' first"; exit 1; }
	rm -f $(NOTARIZE_ZIP)
	ditto -c -k --keepParent $(APP) $(NOTARIZE_ZIP)
	xcrun notarytool submit $(NOTARIZE_ZIP) --keychain-profile $(NOTARY_PROFILE) --wait
	rm -f $(NOTARIZE_ZIP)
	xcrun stapler staple $(APP)
	spctl -a -vvv -t exec $(APP)

# The "drag to Applications" disk image for first downloads. The name carries no version
# so the stable URL .../releases/latest/download/neowall.dmg always resolves.
# create-dmg (brew install create-dmg) lays the window out through Finder, so this needs
# a logged-in GUI session.
dmg:
	@test -d $(APP) || { echo "ERROR: $(APP) not found — run 'make release' first"; exit 1; }
	rm -f $(DMG)
	create-dmg \
	  --volname "$(APP_NAME)" \
	  --volicon $(ICON) \
	  --window-pos 200 120 \
	  --window-size 515 380 \
	  --icon-size 128 \
	  --text-size 12 \
	  --icon "$(APP_NAME).app" 130 190 \
	  --hide-extension "$(APP_NAME).app" \
	  --app-drop-link 385 190 \
	  --format UDZO \
	  $(DMG) $(APP)
	$(CODESIGN) $(DMG)

# The disk image is a downloaded file of its own, checked when it is mounted, so it needs
# its own ticket besides the one inside the app.
notarize-dmg: check-devid
	@test -f $(DMG) || { echo "ERROR: $(DMG) not found — run 'make dmg' first"; exit 1; }
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DMG)
	xcrun stapler validate $(DMG)
