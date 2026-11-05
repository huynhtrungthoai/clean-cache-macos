#!/bin/bash
# ============================================================
# CleanPilot (native SwiftUI) one-shot packaging
#
# Usage:
#   bash build.sh                        default: arm64 + auto-detected signing identity
#   ARCH=universal bash build.sh         arm64 + x86_64 universal (build each triple, then lipo)
#   CHANNEL=appstore bash build.sh       App Store: sandboxed, outputs .pkg, uses Apple Distribution
#                                        (pricing display is a separate switch, see Sources/DiskCleaner/Product.swift)
#   NOTARIZE=1 bash build.sh             submit to Apple notarization and staple (needs credentials below; not for App Store)
#   RELEASE=1 bash build.sh              release build: fail if no Developer ID / Apple Distribution identity;
#                                        never silently ship an ad-hoc or development-signed build
#   DEV_HOOKS=1 bash build.sh            compile in DISKWISE_* dev hooks (screenshots/perf probe/fake home).
#                                        Never in normal builds: some hooks really delete files without confirmation
#   DEV_SIGN_IDENTITY="Apple Development: ..."  which development certificate to use for local builds
#                                        (defaults to the personal huynhtrungthoai@gmail.com one only)
#   SIGN_ACCOUNT_ID=XXXXXXXXXX           Apple ID of the personal account allowed to sign
#                                        (default HN2G8HJ96Q = huynhtrungthoai@gmail.com). Any other
#                                        certificate in the keychain is never auto-picked; if the signed
#                                        TeamIdentifier doesn't match this account, the build fails
#
# Signing identity: one certificate per channel, used automatically if present in the keychain -
# direct download uses "Developer ID Application: ...", App Store uses "Apple Distribution: ...".
# If none is found (non-RELEASE): direct build falls back to "Apple Development: ..." (a free personal cert is fine; stable identity,
# so Full Disk Access/Automation grants survive rebuilds; local use only, cannot be notarized), then ad-hoc.
# Force ad-hoc with SIGN_IDENTITY=none.
#
# Notarization credentials (pick one; never committed to the repo):
#   NOTARY_PROFILE=<name>        recommended: run once
#                              xcrun notarytool store-credentials cleanpilot --apple-id ... --team-id ...
#   or the APPLE_ID + APPLE_TEAM_ID + APP_SPECIFIC_PASSWORD env vars
#   or CI secrets: APPLE_ID / APPLE_TEAM_ID / APP_SPECIFIC_PASSWORD
#
# Requirements: Xcode Command Line Tools only. Note `swift build --arch arm64 --arch x86_64`
# needs xcbuild (full Xcode only), so universal builds use --triple twice + lipo.
#
# Build gates; any failure means no artifact:
#   1. per-language coverage (a missing translation fails the build; otherwise it silently falls back)
#   2. swift run SelfTest (full logic self-test)
#   3. resource assertions (knowledge base + icon + translation dirs)
#   4. universal: both slices present, and the x86_64 one actually runs
#   5. codesign --verify --strict (no shipping with a broken signature)
# ============================================================
set -euo pipefail

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$BUILD_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGING="$BUILD_DIR/staging"
# Signing inputs generated at build time (derived entitlements, decoded provisioning profile) go here,
# kept with the signed build so you can later check which entitlements it was signed with.
DERIVED_DIR="$BUILD_DIR/derived"

APP_NAME="CleanPilot"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
VERSION="1.0"
MIN_MACOS="13.0"
# Personal bundle ID (account huynhtrungthoai). Keep in sync with Sources/DiskCleaner/Product.swift.
BUNDLE_ID="com.huynhtrungthoai.cleanpilot"
VOLNAME="${APP_NAME}"
# Compile flag -DAPPSTORE: App Store build is sandboxed, outputs .pkg, signs with Apple Distribution.
# It does not control pricing display - that is `Channel.showsPricing`, see Sources/DiskCleaner/Product.swift.
CHANNEL="${CHANNEL:-oss}"
SWIFT_FLAGS=""
ARTIFACT_SUFFIX=""
ENTITLEMENTS="$BUILD_DIR/entitlements.plist"
# If upload is rejected for a duplicate version + build pair, rebuild with BUILD_NUMBER=2
BUILD_NUMBER="${BUILD_NUMBER:-$VERSION}"
if [ "${DEV_HOOKS:-0}" = 1 ]; then
	SWIFT_FLAGS="-Xswiftc -DDISKWISE_DEV_HOOKS"
	echo "==> DEV_HOOKS=1: DISKWISE_* dev hooks compiled into this build (screenshots/debugging only, do not release)"
fi
if [ "$CHANNEL" = "appstore" ]; then
	SWIFT_FLAGS="$SWIFT_FLAGS -Xswiftc -DAPPSTORE"
	ARTIFACT_SUFFIX="-appstore"
	ENTITLEMENTS="$BUILD_DIR/entitlements-appstore.plist"
fi

# -- Architecture ------------------------------------------------------------
# universal artifacts get a -universal suffix; arm64 keeps the old name (old download links keep working).
ARCH="${ARCH:-arm64}"
case "$ARCH" in
	arm64)    ARCH_SUFFIX="" ;            ARCH_TRIPLE="arm64-apple-macos$MIN_MACOS" ;;
	x86_64)   ARCH_SUFFIX="-intel" ;      ARCH_TRIPLE="x86_64-apple-macos$MIN_MACOS" ;;
	universal) ARCH_SUFFIX="-universal" ; ARCH_TRIPLE="" ;;
	*) echo "Error: ARCH must be arm64 / x86_64 / universal, got '$ARCH'" >&2; exit 1 ;;
esac
DMG_NAME="${APP_NAME}-$VERSION${ARCH_SUFFIX}${ARTIFACT_SUFFIX}.dmg"
PKG_NAME="${APP_NAME}-$VERSION${ARCH_SUFFIX}${ARTIFACT_SUFFIX}.pkg"

RES_DIR="$ROOT_DIR/Sources/DiskCleaner/Resources"

echo "==> [1/7] Localization coverage check"
cd "$ROOT_DIR"
swift "$ROOT_DIR/build_app/l10n_tool.swift" check | sed 's/^/    /'

echo "==> [2/7] App icon (generated parametrically, no external assets)"
ICONSET="$BUILD_DIR/AppIcon.iconset"
ICNS="$BUILD_DIR/AppIcon.icns"
if [ ! -f "$ICNS" ] || [ "$BUILD_DIR/make_icon.swift" -nt "$ICNS" ]; then
	rm -rf "$ICONSET"
	swift "$BUILD_DIR/make_icon.swift" "$ICONSET" | sed 's/^/    /'
	iconutil -c icns -o "$ICNS" "$ICONSET"
	echo "    AppIcon.icns: $(du -h "$ICNS" | cut -f1)"
else
	echo "    Reusing existing AppIcon.icns (regenerated automatically when make_icon.swift changes)"
fi

# Build one triple; stdout returns only the product dir (progress goes to stderr, else $(...) swallows it)
# Keep the full compile log and check the exit code right away: tailing a few lines cuts off the real error,
# and the function's return code is that of the last command (the bin-path query), so it returns 0 even if compilation fails.
build_for_triple() {
	local triple="$1"
	# One scratch dir per slice, passed explicitly to --show-bin-path. In Xcode 27's SwiftPM
	# --show-bin-path ignores --triple, so both slices report the same .build/out/Products/Release,
	# the second overwrites the first, and universal degrades to one arch (lipo dies with "same architectures";
	# worse, the cache decides "no rebuild needed" and a fake single-slice universal build ships).
	local scratch="$ROOT_DIR/.build/$triple"
	local log="$ROOT_DIR/.build/compile.$triple.log"
	mkdir -p "$(dirname "$log")"
	if ! swift build -c release --scratch-path "$scratch" --triple "$triple" $SWIFT_FLAGS >"$log" 2>&1; then
		echo "    $triple compile failed, $(wc -l < "$log" | tr -d ' ') lines of output, last 60:" >&2
		tail -n 60 "$log" | sed 's/^/    /' >&2
		exit 1
	fi
	tail -n 2 "$log" >&2
	swift build --show-bin-path -c release --scratch-path "$scratch" --triple "$triple" 2>/dev/null | tail -n 1
}

echo "==> [3/7] Release compile (arch ${ARCH}, channel ${CHANNEL})"
BIN="$ROOT_DIR/.build/release/DiskCleaner"          # the binary that goes into the bundle
CLI_BIN=""                                          # Agent CLI executable (bundled in direct build; App Store only compiles it)
if [ -n "$ARCH_TRIPLE" ]; then
	SINGLE="$(build_for_triple "$ARCH_TRIPLE")"
	BIN="$SINGLE/DiskCleaner"
	[ -x "$BIN" ] || { echo "Error: build product $BIN not found" >&2; exit 1; }
	lipo -info "$BIN" | sed 's/^/    /'
	"$SINGLE/SelfTest" 2>&1 | tail -n 1 | sed 's/^/    /'
	CLI_BIN="$SINGLE/DiskWiseCLI"
else
	# Two --arch values need xcbuild (CLT lacks it), so build each triple and merge manually.
	ARM_BIN_DIR="$(build_for_triple "arm64-apple-macos$MIN_MACOS")"
	X86_BIN_DIR="$(build_for_triple "x86_64-apple-macos$MIN_MACOS")"
	ARM_BIN="$ARM_BIN_DIR/DiskCleaner"
	X86_BIN="$X86_BIN_DIR/DiskCleaner"
	for f in "$ARM_BIN" "$X86_BIN"; do
		[ -x "$f" ] || { echo "Error: universal build missing a slice, $f does not exist" >&2; exit 1; }
	done
	# Self-test each thin slice first: after merging you can't tell which slice broke
	if ARM_LOG="$("$ARM_BIN_DIR/SelfTest" 2>&1)"; then
		printf '%s\n' "    arm64   $(printf '%s' "$ARM_LOG" | tail -n 1)"
	elif printf '%s' "$ARM_LOG" | grep -q "Bad CPU type"; then
		# Since macOS 26, Intel machines can't install Rosetta (softwareupdate --install-rosetta returns
		# "not supported"), so the arm64 slice can only be compiled, not executed, on such machines.
		# What's skipped is execution, not shipping: release.yml's macos-14 runner is Apple Silicon,
		# so that slice's SelfTest runs natively there; dispatch it manually once before releasing.
		echo "    arm64   self-test skipped: Intel host without Rosetta support (runs on the CI macos-14 runner)"
	else
		echo "Error: arm64 slice failed self-test, cannot ship" >&2
		printf '%s\n' "$ARM_LOG" | tail -n 6 >&2
		exit 1
	fi
	if X86_LOG="$("$X86_BIN_DIR/SelfTest" 2>&1)"; then
		printf '%s\n' "    x86_64  $(printf '%s' "$X86_LOG" | tail -n 1)"
	elif printf '%s' "$X86_LOG" | grep -q "Bad CPU type"; then
		echo "    x86_64  self-test skipped: Rosetta not installed (runs on the CI arm64 runner)"
	else
		echo "Error: x86_64 slice failed self-test, cannot ship" >&2
		printf '%s\n' "$X86_LOG" | tail -n 6 >&2
		exit 1
	fi
	lipo -create -output "$BUILD_DIR/DiskCleaner.universal" "$ARM_BIN" "$X86_BIN"
	BIN="$BUILD_DIR/DiskCleaner.universal"
	lipo -info "$BIN" | sed 's/^/    /'
	ARCHS_IN="$(lipo -archs "$BIN")"
	printf '%s\n' "$ARCHS_IN" | grep -qw arm64 \
		|| { echo "Error: merged binary has no arm64 slice, got '$ARCHS_IN'" >&2; exit 1; }
	printf '%s\n' "$ARCHS_IN" | grep -qw x86_64 \
		|| { echo "Error: merged binary has no x86_64 slice, got '$ARCHS_IN'" >&2; exit 1; }
	# Agent CLI is merged the same way (same triple pair as the main app)
	lipo -create -output "$BUILD_DIR/DiskWiseCLI.universal" \
		"$ARM_BIN_DIR/DiskWiseCLI" "$X86_BIN_DIR/DiskWiseCLI"
	CLI_BIN="$BUILD_DIR/DiskWiseCLI.universal"
fi
# swift build compiles DiskWiseCLI too; only assert it exists here, the channel decides whether it's bundled
[ -n "$CLI_BIN" ] && [ -x "$CLI_BIN" ] \
	|| { echo "Error: DiskWiseCLI build product (Agent CLI binary) not found" >&2; exit 1; }
echo "    Binary: $(du -h "$BIN" | cut -f1)"

echo "==> [4/7] Assembling ${APP_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/DiskCleaner"
# Only the direct build bundles the CLI (renamed to diskwise); the sandboxed App Store build doesn't -
# in the sandbox the CLI has no home-folder grant and can't scan, so a dead entry point is worse than none
if [ "$CHANNEL" != "appstore" ]; then
	cp "$CLI_BIN" "$APP_DIR/Contents/MacOS/diskwise"
	[ -x "$APP_DIR/Contents/MacOS/diskwise" ] \
		|| { echo "Error: diskwise CLI missing from .app" >&2; exit 1; }
fi
cp "$ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$RES_DIR/safety_db.json" "$APP_DIR/Contents/Resources/"
cp "$RES_DIR/skins.json" "$APP_DIR/Contents/Resources/"
# All languages ship at once: a missing one silently falls back while the build still succeeds. So check dir counts below.
for LPROJ in "$RES_DIR"/*.lproj; do
	cp -R "$LPROJ" "$APP_DIR/Contents/Resources/"
done
cp -R "$RES_DIR/BrandIcons" "$APP_DIR/Contents/Resources/"
# The whole Caches page comes from this knowledge base; losing it won't crash, but the page goes silently blank
[ -f "$APP_DIR/Contents/Resources/safety_db.json" ] \
	|| { echo "Error: safety_db.json missing from .app, Caches page would be empty" >&2; exit 1; }
# Losing the skin catalog won't crash, but all six skins vanish, leaving only the plain built-in one
[ -f "$APP_DIR/Contents/Resources/skins.json" ] \
	|| { echo "Error: skins.json missing from .app, Skins page would only have the built-in fallback skin" >&2; exit 1; }
# A missing icon raises no error; the Dock just shows the generic blank icon - exactly the "bare build" to avoid
[ -f "$APP_DIR/Contents/Resources/AppIcon.icns" ] \
	|| { echo "Error: AppIcon.icns missing from .app, Dock would show the generic icon" >&2; exit 1; }
# A missing translation dir raises no error; that language just falls back entirely - a silent release means no localization.
# Check two levels: dir count and a string table per language, not just whether en exists.
LPROJ_N_IN=$(find "$RES_DIR" -maxdepth 1 -name '*.lproj' | wc -l | tr -d ' ')
LPROJ_N_OUT=$(find "$APP_DIR/Contents/Resources" -maxdepth 1 -name '*.lproj' | wc -l | tr -d ' ')
[ "$LPROJ_N_IN" = "$LPROJ_N_OUT" ] && [ "$LPROJ_N_OUT" != "0" ] \
	|| { echo "Error: only $LPROJ_N_OUT/$LPROJ_N_IN language dirs made it in" >&2; exit 1; }
for LPROJ in "$APP_DIR/Contents/Resources"/*.lproj; do
	# Every language directory, en included, ships its own Localizable.strings
	[ -f "$LPROJ/Localizable.strings" ] \
		|| { echo "Error: $(basename "$LPROJ")/Localizable.strings missing from .app, that language would fall back to English" >&2; exit 1; }
done
# Missing brand icons won't crash either; rows without a .app (Ollama, uv, JetBrains...) silently fall back to the generic folder,
# i.e. the row of identical blue folders we set out to remove - so check file count, not dir existence.
BRAND_N_IN=$(find "$RES_DIR/BrandIcons" -name '*.png' | wc -l | tr -d ' ')
BRAND_N_OUT=$(find "$APP_DIR/Contents/Resources/BrandIcons" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
[ "$BRAND_N_IN" = "$BRAND_N_OUT" ] && [ "$BRAND_N_OUT" != "0" ] \
	|| { echo "Error: only $BRAND_N_OUT/$BRAND_N_IN BrandIcons made it in; tool rows without a .app would fall back to the generic folder" >&2; exit 1; }

# CFBundleLocalizations follows the language dirs: with a hardcoded list, adding a language means editing two places,
# and sooner or later one misses system-level language matching.
LOCALIZATIONS=""
for LPROJ in "$RES_DIR"/*.lproj; do
	LOCALIZATIONS="${LOCALIZATIONS}		<string>$(basename "$LPROJ" .lproj)</string>
"
done

cat > "$APP_DIR/Contents/Info.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>DiskCleaner</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleLocalizations</key>
	<array>
$LOCALIZATIONS	</array>
	<key>LSMinimumSystemVersion</key>
	<string>$MIN_MACOS</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>CleanPilot — based on DiskWise, Apache-2.0</string>
	<key>NSAppleEventsUsageDescription</key>
	<string>CleanPilot asks Finder to empty the Trash. The app never deletes files permanently on its own.</string>
</dict>
</plist>
PLIST_EOF

# Name and descriptions shown in the Dock / permission prompts follow the UI language.
# They live in <lang>.lproj/InfoPlist.strings in the source tree, already copied by the loop above.
[ -f "$APP_DIR/Contents/Resources/en.lproj/InfoPlist.strings" ] \
	|| { echo "error: en.lproj/InfoPlist.strings missing from the .app" >&2; exit 1; }

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
plutil -lint "$ENTITLEMENTS" >/dev/null

echo "==> [5/7] Signing"
# One certificate per channel: direct download needs Developer ID Application, App Store needs Apple Distribution.
# Signing with the wrong one can't be uploaded or installed where it's meant to go.
if [ "$CHANNEL" = "appstore" ]; then
	IDENT_PATTERN="Apple Distribution:"
else
	IDENT_PATTERN="Developer ID Application:"
fi
# Personal signing only (huynhtrungthoai@gmail.com). Any other certificate in the keychain
# must never be picked automatically. Developer ID / Apple Distribution identities carry the
# account ID in their name ("Name (ID)"), so auto-detection requires the personal account's suffix.
SIGN_ACCOUNT_ID="${SIGN_ACCOUNT_ID:-HN2G8HJ96Q}"
DEV_SIGN_IDENTITY="${DEV_SIGN_IDENTITY:-Apple Development: huynhtrungthoai@gmail.com}"
# SIGN_IDENTITY=none forces ad-hoc (to test the fallback path)
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
	IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
		| awk -F'"' -v pat="$IDENT_PATTERN" -v team="($SIGN_ACCOUNT_ID)" \
			'index($2, pat) == 1 && substr($2, length($2) - length(team) + 1) == team {print $2; exit}')" || true
fi
# SIGN_MODE: dist = Developer ID / Apple Distribution (shippable)
#            dev  = Apple Development (stable local identity, not distributable/notarizable)
#            adhoc
SIGN_MODE=""
if [ -n "$IDENTITY" ] && [ "$IDENTITY" != "none" ]; then
	case "$IDENTITY" in "$IDENT_PATTERN"*) SIGN_MODE="dist" ;; *) SIGN_MODE="dev" ;; esac
fi
if [ -z "$IDENTITY" ] && [ "${RELEASE:-0}" != 1 ] && [ "$CHANNEL" != "appstore" ]; then
	# Prefix match on the personal account's development certificate only.
	IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
		| awk -F'"' -v pat="$DEV_SIGN_IDENTITY" 'index($2, pat) == 1 {print $2; exit}')" || true
	[ -n "$IDENTITY" ] && SIGN_MODE="dev"
fi
if [ "$IDENTITY" = "none" ]; then IDENTITY=""; SIGN_MODE=""; fi
[ -z "$IDENTITY" ] && SIGN_MODE="adhoc"
if [ "${RELEASE:-0}" = 1 ] && [ "$SIGN_MODE" != "dist" ]; then
	echo "Error: RELEASE=1 requires a \"$IDENT_PATTERN ...\" identity, current mode is $SIGN_MODE." >&2
	echo "      Release builds can't be ad-hoc or development-signed (Gatekeeper blocks them; users must click \"Open Anyway\")." >&2
	exit 1
fi

# App Store build: the provisioning profile must be in place before signing; it binds the sandbox entitlements to the App ID.
PROFILE="${PROVISION_PROFILE:-$BUILD_DIR/diskwise-appstore.provisionprofile}"
if [ "$CHANNEL" = "appstore" ]; then
	if [ -f "$PROFILE" ]; then
		cp "$PROFILE" "$APP_DIR/Contents/embedded.provisionprofile"
		echo "    Provisioning profile: $(basename "$PROFILE") ($(du -h "$APP_DIR/Contents/embedded.provisionprofile" | cut -f1))"
		# The App Store build must carry the App ID entitlement granted by the profile. On macOS this key
		# is com.apple.application-identifier (TN3125: only iOS uses the unprefixed
		# application-identifier); shipped apps like Keynote / GarageBand / Notion all have it.
		# Signing passes without it, but App Store's "signature matches profile" check depends on it.
		mkdir -p "$DERIVED_DIR"
		DEC_PROFILE="$DERIVED_DIR/provisionprofile.plist"
		security cms -D -i "$PROFILE" -o "$DEC_PROFILE"
		PROFILE_APPID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$DEC_PROFILE" 2>/dev/null || true)"
		PROFILE_TEAM="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$DEC_PROFILE" 2>/dev/null || true)"
		if [ -z "$PROFILE_APPID" ] || [ -z "$PROFILE_TEAM" ]; then
			echo "    Error: can't read App ID / Team ID from the provisioning profile; cannot sign this build" >&2
			exit 1
		fi
		case "$PROFILE_APPID" in
			*.*) ;;
			*)
				echo "    Error: App ID in the provisioning profile doesn't look like TEAM.bundleid: $PROFILE_APPID" >&2
				exit 1
				;;
		esac
		# A profile may bind an exact App ID or a wildcard (TEAM com.foo.*)
		PROFILE_BUNDLE="${PROFILE_APPID#*.}"
		if [ "$PROFILE_BUNDLE" = "$BUNDLE_ID" ]; then
			:
		elif [[ "$PROFILE_BUNDLE" == *.\* && "$BUNDLE_ID" == "${PROFILE_BUNDLE%?}"* ]]; then
			:
		else
			echo "    Error: provisioning profile is bound to App ID ${PROFILE_APPID}, not this build's $BUNDLE_ID" >&2
			echo "    Use a profile for this bundle id (portal Profiles -> Edit -> pick the right App ID)" >&2
			exit 1
		fi
		ENTITLEMENTS="$DERIVED_DIR/entitlements-appstore.plist"
		cp "$BUILD_DIR/entitlements-appstore.plist" "$ENTITLEMENTS"
		for k in "com.apple.application-identifier=$PROFILE_APPID" "com.apple.developer.team-identifier=$PROFILE_TEAM"; do
			/usr/libexec/PlistBuddy -c "Set :${k%%=*} ${k#*=}" "$ENTITLEMENTS" 2>/dev/null \
				|| /usr/libexec/PlistBuddy -c "Add :${k%%=*} string ${k#*=}" "$ENTITLEMENTS" >/dev/null
		done
		plutil -lint "$ENTITLEMENTS" >/dev/null
		echo "    App ID entitlement: ${PROFILE_APPID} (team ${PROFILE_TEAM})"
	else
		echo "    No provisioning profile ($PROFILE not found) - runs locally, but this build can't be uploaded to App Store Connect"
	fi
fi

# Profiles are downloaded from the portal in a browser and carry com.apple.quarantine; the cp above carries it
# into the payload, productbuild bakes it into the pkg, and App Store processing rejects the whole package with 91109
# ("This attribute isn't permitted in macOS apps distributed on TestFlight or the App Store").
# Remove only this attribute - com.apple.provenance is recorded by the system and shouldn't (and can't) be cleared.
QFILES="$(find "$APP_DIR" -exec sh -c 'xattr "$1" 2>/dev/null | grep -qx com.apple.quarantine && echo q' _ {} \; | wc -l | tr -d ' ')"
if [ "$QFILES" != "0" ]; then
	echo "    Clearing quarantine attribute: $QFILES files"
	xattr -r -d com.apple.quarantine "$APP_DIR" 2>/dev/null || true
fi

# The nested diskwise executable must be signed on its own before the bundle: codesign doesn't recurse (--deep is
# explicitly discouraged by Apple), and notarization requires nested code to carry its own signature. The ad-hoc branch signs it first too -
# otherwise the codesign --verify --strict below fails locally before notarization is even reached.
if [ -f "$APP_DIR/Contents/MacOS/diskwise" ]; then
	if [ "$SIGN_MODE" = "dist" ]; then
		codesign --force --options runtime --timestamp \
			--sign "$IDENTITY" "$APP_DIR/Contents/MacOS/diskwise"
	elif [ "$SIGN_MODE" = "dev" ]; then
		codesign --force --options runtime --sign "$IDENTITY" "$APP_DIR/Contents/MacOS/diskwise"
	else
		codesign --force --options runtime --sign - "$APP_DIR/Contents/MacOS/diskwise"
	fi
fi

SIGNED=0
if [ "$SIGN_MODE" = "dev" ]; then
	# SIGNED stays 0: a development certificate cannot be notarized or shipped. It only gives
	# this Mac a stable code identity so TCC grants (Full Disk Access, Automation) survive rebuilds.
	echo "    Development certificate (local only): $IDENTITY"
	codesign --force --options runtime \
		--entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_DIR"
elif [ -n "$IDENTITY" ]; then
	SIGNED=1
	echo "    Identity: $IDENTITY"
	# --deep is explicitly discouraged by Apple; the nested diskwise executable was signed separately above,
	# so sign the bundle directly. Hardened runtime + secure timestamp are hard notarization requirements; notarytool rejects without either.
	codesign --force --options runtime --timestamp \
		--entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_DIR"
else
	echo "    No $IDENT_PATTERN in keychain -> ad-hoc signing"
	if [ "$CHANNEL" = "appstore" ]; then
		echo "    Sandbox still applies (grant flows can be tested locally), but this build can't be uploaded; testing only."
	else
		echo "    Artifact still produced, but Gatekeeper blocks the first launch once; cannot be notarized."
	fi
	codesign --force --options runtime --sign - --entitlements "$ENTITLEMENTS" "$APP_DIR"
fi
codesign --verify --strict --verbose=2 "$APP_DIR" 2>&1 | tail -n 1 | sed 's/^/    /'
# Smoke test: the signed CLI actually runs (App Store build has no CLI, skipped)
if [ -f "$APP_DIR/Contents/MacOS/diskwise" ]; then
	"$APP_DIR/Contents/MacOS/diskwise" --version | sed 's/^/    CLI smoke test: /'
fi
# Direct-build entitlements are an empty dict; a grep miss under set -e would kill the build, so capture into a variable first.
ENT_SUMMARY="$(plutil -p "$ENTITLEMENTS" | grep -E 'app-sandbox|user-selected|apple-events|application-identifier|team-identifier' || true)"
if [ -n "$ENT_SUMMARY" ]; then
	echo "$ENT_SUMMARY" | sed 's/^/    /'
else
	echo "    entitlements: empty dict (direct build's hardened runtime needs no keys)"
fi
codesign -dv --verbose=4 "$APP_DIR" 2>&1 \
	| grep -E "^(Identifier|Format|CodeDirectory)|Signature=|TeamIdentifier|Runtime" \
	| sed 's/^/    /'
# Guard: a signed bundle must belong to the personal account, never another identity that happens to have
# a certificate in this keychain (explicit SIGN_IDENTITY included).
if [ "$SIGN_MODE" != "adhoc" ]; then
	for BIN in "$APP_DIR" "$APP_DIR/Contents/MacOS/diskwise"; do
		[ -e "$BIN" ] || continue
		GOT_TEAM="$(codesign -dv --verbose=4 "$BIN" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
		if [ "$GOT_TEAM" != "$SIGN_ACCOUNT_ID" ]; then
			echo "Error: $(basename "$BIN") was signed with team '$GOT_TEAM', only '$SIGN_ACCOUNT_ID' (personal account huynhtrungthoai) is allowed." >&2
			echo "      Check SIGN_IDENTITY / DEV_SIGN_IDENTITY, or use SIGN_IDENTITY=none for ad-hoc." >&2
			exit 1
		fi
	done
	echo "    Account check: $SIGN_ACCOUNT_ID (huynhtrungthoai) ✓"
fi

echo "==> [6/7] Assembling release artifact"
mkdir -p "$DIST_DIR"
if [ "$CHANNEL" = "appstore" ]; then
	# The App Store only accepts .pkg (Transporter / altool don't take DMGs), so this branch makes no DMG
	# and no README.txt - that first-launch note is only for direct downloads.
	# The two certificates can't be mixed: .app uses Apple Distribution, .pkg must be signed with Mac Installer
	# Distribution (a fixed split in Apple's certificate table); with the wrong identity productbuild fails.
	ARTIFACT="$DIST_DIR/$PKG_NAME"
	INSTALLER_IDENT=""
	if [ "$SIGNED" = 1 ]; then
		# Don't add -p codesigning here: installer identities aren't in the codesigning policy,
		# and that filter would drop Mac Installer Distribution entirely (Apple's packaging docs warn about this).
		INSTALLER_IDENT="$(security find-identity -v 2>/dev/null \
			| awk -F'"' 'index($2, "Mac Installer Distribution:") == 1 ||
					index($2, "3rd Party Mac Developer Installer:") == 1 {print $2; exit}')" || true
	fi
	# productbuild hands the component to a system packaging helper, and ~/Desktop is TCC-protected: with the repo
	# on the Desktop, the same .app fails with "not a valid bundle component" but works elsewhere.
	# So copy it to a temp dir first - the signature travels with the dir and the path isn't in the artifact.
	PKG_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/diskwise-pkg.XXXXXX")"
	ditto "$APP_DIR" "$PKG_STAGE/${APP_NAME}.app"
	COMPONENT="$PKG_STAGE/${APP_NAME}.app"
	PKG_LOG="$BUILD_DIR/productbuild.log"
	if [ -n "$INSTALLER_IDENT" ] && productbuild --component "$COMPONENT" /Applications \
			--sign "$INSTALLER_IDENT" "$ARTIFACT" >"$PKG_LOG" 2>&1; then
		echo "    pkg signed: $INSTALLER_IDENT"
	else
		rm -f "$ARTIFACT"
		if ! productbuild --component "$COMPONENT" /Applications "$ARTIFACT" >>"$PKG_LOG" 2>&1; then
			# Without catching this, set -e exits silently here, leaving only a "[6/7]" line
			echo "    pkg build failed, productbuild output:"
			sed 's/^/      /' "$PKG_LOG" | tail -6
			rm -rf "$PKG_STAGE"
			exit 1
		fi
		if [ "$SIGNED" != 1 ]; then
			echo "    pkg unsigned: the app itself is ad-hoc; only for testing grant flows locally"
		elif [ -z "$INSTALLER_IDENT" ]; then
			echo "    pkg unsigned: app is signed, but no \"Mac Installer Distribution: ...\" in the keychain"
			echo "    The App Store requires the product archive be signed with this cert; Transporter rejects without it - create one in the portal, same CSR is fine"
		else
			echo "    pkg signing failed, productbuild output:"
			sed 's/^/      /' "$PKG_LOG" | tail -6
		fi
	fi
	rm -rf "$PKG_STAGE"
	echo "    ${PKG_NAME}: $(du -h "$ARTIFACT" | cut -f1)"
else
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

if [ "${NOTARIZE:-0}" = 1 ]; then
	# Safe to write this early: step 7 hard-fails without identity/credentials, so no build claims notarization it lacks
	LAUNCH_EN='[ First launch ]
Double-click it. The build is signed by a Developer ID identity and notarized by
Apple, so Gatekeeper lets it open with no extra step.'
	HEADER_EN="signed + notarized"
else
	# Signed is not notarized: a downloaded build without a ticket is still blocked by Gatekeeper, so the text must not claim otherwise
	if [ "$SIGNED" = 1 ]; then
		HEADER_EN="signed, NOT notarized"
	else
		HEADER_EN="unsigned"
	fi
	LAUNCH_EN="[ First launch ($HEADER_EN) ]
Double-click is blocked the first time. Then open
System Settings -> Privacy & Security -> \"Open Anyway\" -> Open.
(On macOS 13-14 the older right-click -> Open works too;
Sequoia removed that shortcut.)"
fi

cat > "$STAGING/README.txt" <<README_EOF
${APP_NAME} v$VERSION (native SwiftUI, $HEADER_EN)
============================================================

[ What this is ]
A native macOS app — no Python, no local server, no ports.
It shows where your disk space went, explains every item
("what is this / what happens if I delete it / how do I get it back"),
and only ever moves things to the Trash. Undo anytime.
No network, no telemetry, no ads.

[ Install ]
1. Open this DMG.
2. Drag "${APP_NAME}.app" into the Applications folder.
3. Eject the DMG.

$LAUNCH_EN

[ Emptying the Trash ]
That step is handed to Finder, which asks for automation permission the
first time. Click OK. (Change it later in
System Settings -> Privacy & Security -> Automation.)

[ Switch language ]
Skins page -> globe control -> pick a language. Applies at once, no restart.

[ Uninstall ]
Drag the app to the Trash. No leftovers, no background agents.
README_EOF

hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDZO "$DIST_DIR/$DMG_NAME" >/dev/null
ARTIFACT="$DIST_DIR/$DMG_NAME"
echo "    ${DMG_NAME}: $(du -h "$ARTIFACT" | cut -f1)"
fi

echo "==> [7/7] Notarization"
if [ "$CHANNEL" = "appstore" ]; then
	echo "    Skipped: Apple notarizes App Store builds after upload; stapling is redundant (a stapled pkg is actually a rejection point)"
	ART_SHA="$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')"
elif [ "${NOTARIZE:-0}" != 1 ]; then
	if [ "$SIGNED" = 1 ]; then
		echo "    Signed but not notarized (for a double-click-to-open build: NOTARIZE=1 bash build.sh)"
	else
		echo "    Skipped: $SIGN_MODE-signed builds can't be notarized (needs a Developer ID Application cert on the personal account)"
	fi
	ART_SHA="$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')"
else
	[ "$SIGNED" = 1 ] || {
		echo "Error: notarization needs a Developer ID Application identity, only ad-hoc available." >&2
		echo "      Create the certificate in Keychain Access, then rerun; or export SIGN_IDENTITY=\"Developer ID Application: ...\"" >&2
		exit 1
	}
	# The DMG itself must be signed too; it's the container that gets notarized
	codesign --force --timestamp --sign "$IDENTITY" "$ARTIFACT"

	if [ -n "${NOTARY_PROFILE:-}" ]; then
		xcrun notarytool submit "$ARTIFACT" --keychain-profile "$NOTARY_PROFILE" --wait
	elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
		xcrun notarytool submit "$ARTIFACT" \
			--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APP_SPECIFIC_PASSWORD" --wait
	else
		echo "Error: no notarization credentials. Pick one:" >&2
		echo "      1) store once in the keychain, then just set NOTARY_PROFILE: export NOTARY_PROFILE=cleanpilot" >&2
		echo "         xcrun notarytool store-credentials cleanpilot --apple-id YOUR_EMAIL --team-id TEAMID --password xxxx-xxxx-xxxx-xxxx" >&2
		echo "      2) export APPLE_ID / APPLE_TEAM_ID / APP_SPECIFIC_PASSWORD (create the app-specific password at appleid.apple.com)" >&2
		echo "      3) on CI, configure these three as secrets" >&2
		exit 1
	fi

	xcrun stapler staple "$ARTIFACT"
	xcrun stapler validate "$ARTIFACT" 2>&1 | tail -n 1 | sed 's/^/    /'
	# This is the same check Gatekeeper runs when the user double-clicks
	spctl --assess --type open --context context:primary-signature -vv "$ARTIFACT" 2>&1 | sed 's/^/    /'
	ART_SHA="$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')"
fi

echo "---- Done ----"
ls -lh "$ARTIFACT"
echo "SHA256: $ART_SHA"
