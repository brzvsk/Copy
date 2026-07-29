#!/usr/bin/env bash
#
# release.sh -- build a notarized, Developer ID signed Copy.app DMG plus a
# Sparkle update enclosure for a tagged release.
#
# Usage: Scripts/release.sh <version> [--dry-run]
#   <version>   marketing version, e.g. 0.1.0 (no leading "v")
#   --dry-run   stop once the DMG is built and signed, before notarizing,
#               stapling, building the Sparkle enclosure, or printing the
#               publish command. Everything up to and including the DMG is
#               still built for real with the Developer ID identity; only
#               notarization and anything after it is skipped.
#
# Pipeline: xcodegen generate -> archive (Developer ID, manual signing) ->
# export -> re-sign every embedded framework/xpc/helper inside-out with a
# secure timestamp -> build + sign the DMG -> notarize the DMG -> staple the
# DMG and the .app -> build the Sparkle zip enclosure and sign it -> print an
# appcast <item> snippet (and refresh docs/appcast.xml) -> print (but do not
# run) the `gh release create` command, since publishing is a human step.
#
# Requires locally:
#   - Xcode + xcodegen
#   - A "Developer ID Application" signing identity for team P7V47BUA2B
#   - A notarytool keychain profile (see COPY_NOTARY_PROFILE below)
#   - Sparkle's sign_update binary, resolved automatically from DerivedData
#
# Env vars:
#   COPY_NOTARY_PROFILE   notarytool keychain profile name (default: copy-notary)
set -euo pipefail

usage() {
  echo "Usage: $0 <version> [--dry-run]" >&2
  echo "  <version>   marketing version, e.g. 0.1.0" >&2
  echo "  --dry-run   stop after the DMG is built and signed, before notarizing" >&2
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

VERSION="$1"
shift
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    *)
      echo "error: unknown argument: $arg" >&2
      usage
      ;;
  esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must look like 0.1.0 (got: $VERSION)" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="Copy"
PROJECT="Copy.xcodeproj"
TEAM_ID="P7V47BUA2B"
SIGN_IDENTITY="Developer ID Application"
NOTARY_PROFILE="${COPY_NOTARY_PROFILE:-copy-notary}"
GITHUB_REPO="tarikbc/Copy"

BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Copy.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/Copy.app"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/exportOptions.plist"
DMG_STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/Copy-${VERSION}.dmg"
SPARKLE_ZIP_PATH="$BUILD_DIR/Copy-${VERSION}.zip"
APPCAST_PATH="$ROOT_DIR/docs/appcast.xml"

step() {
  echo ""
  echo "==> $*"
}

step "1/9 Regenerating the Xcode project (xcodegen generate)"
xcodegen generate

mkdir -p "$BUILD_DIR"

step "2/9 Archiving Copy.app (Release, Developer ID signing) -> $ARCHIVE_PATH"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

step "3/9 Writing $EXPORT_OPTIONS_PLIST"
cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>${SIGN_IDENTITY}</string>
</dict>
</plist>
PLIST

step "4/9 Exporting the archive -> $APP_PATH"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: export did not produce $APP_PATH" >&2
  exit 1
fi

# Notarization gotcha (learned the hard way on CamLoop): every embedded
# framework, XPC service, and helper .app must carry its own Developer ID
# signature with a secure timestamp, or notarization rejects the submission
# even though the outer app looks correctly signed. `codesign --deep` does
# not reliably propagate `--timestamp` to nested code, so we sign inside-out
# explicitly: deepest nested bundles/executables first (Sparkle's XPCServices,
# Updater.app, and the bare Autoupdate binary), then the frameworks that
# contain them, then the app last.
step "5/9 Re-signing embedded frameworks/helpers inside-out (hardened runtime + secure timestamp)"

sign_one() {
  local path="$1"
  echo "    codesign: $path"
  codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime --timestamp \
    "$path"
}

FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
if [[ -d "$FRAMEWORKS_DIR" ]]; then
  # Find every nested .framework/.xpc/.app plus bare Mach-O executables
  # (e.g. Sparkle's Autoupdate helper, which isn't wrapped in a bundle),
  # then sign deepest-path-first so containers are signed after their
  # contents.
  nested_paths=()
  while IFS= read -r -d '' path; do
    nested_paths+=("$path")
  done < <(find "$FRAMEWORKS_DIR" \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" \) -print0)

  # Bare executables directly inside a framework's version directory
  # (not part of a .framework/.xpc/.app match above) also need their own
  # signature -- e.g. Sparkle.framework/Versions/B/Autoupdate.
  while IFS= read -r -d '' path; do
    if [[ -x "$path" && ! -d "$path" ]]; then
      nested_paths+=("$path")
    fi
  done < <(find "$FRAMEWORKS_DIR" -type f -perm -u+x -print0)

  # Sort deepest-first by path segment count so nested bundles/executables
  # are signed before the frameworks/apps that contain them. Done as a plain
  # bash insertion sort (the list is a handful of Sparkle helpers) rather
  # than piping through `sort`/`cut`, since their NUL-delimited (-z) modes
  # are GNU-only and unavailable in macOS's BSD toolset.
  if [[ ${#nested_paths[@]} -gt 0 ]]; then
    depth_of() {
      local slashes="${1//[^\/]/}"
      echo "${#slashes}"
    }
    sorted_paths=("${nested_paths[@]}")
    count=${#sorted_paths[@]}
    for ((i = 1; i < count; i++)); do
      current="${sorted_paths[i]}"
      current_depth=$(depth_of "$current")
      j=$((i - 1))
      while (( j >= 0 )) && (( $(depth_of "${sorted_paths[j]}") < current_depth )); do
        sorted_paths[j + 1]="${sorted_paths[j]}"
        j=$((j - 1))
      done
      sorted_paths[j + 1]="$current"
    done
    for path in "${sorted_paths[@]}"; do
      sign_one "$path"
    done
  fi

  # Finally sign each top-level framework itself (e.g. Sparkle.framework),
  # now that everything nested inside it already carries its own signature.
  while IFS= read -r -d '' framework; do
    sign_one "$framework"
  done < <(find "$FRAMEWORKS_DIR" -maxdepth 1 -name "*.framework" -print0)
fi

step "6/9 Signing Copy.app (top-level, last)"
sign_one "$APP_PATH"

echo ""
echo "    Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

step "7/9 Building the DMG -> $DMG_PATH"
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
ditto "$APP_PATH" "$DMG_STAGING_DIR/Copy.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "Copy" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

echo ""
echo "    Signing the DMG..."
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "==> --dry-run: stopping before notarization."
  echo "    Built and signed: $DMG_PATH"
  echo "    What would happen next (real run, no --dry-run):"
  echo "      8/9 xcrun notarytool submit \"$DMG_PATH\" --keychain-profile \"$NOTARY_PROFILE\" --wait"
  echo "          then: xcrun stapler staple \"$DMG_PATH\" && xcrun stapler staple \"$APP_PATH\""
  echo "      9/9 ditto -c -k --keepParent \"$APP_PATH\" \"$SPARKLE_ZIP_PATH\""
  echo "          then: sign_update \"$SPARKLE_ZIP_PATH\" (Sparkle EdDSA signature)"
  echo "          then: print an appcast <item> snippet, refresh $APPCAST_PATH"
  echo "          then: print (not run) the gh release create command"
  exit 0
fi

step "8/9 Notarizing and stapling"
echo "    Submitting $DMG_PATH to notarytool (profile: $NOTARY_PROFILE)..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo ""
echo "    Stapling the DMG..."
xcrun stapler staple "$DMG_PATH"

# The notarization submission covers every signed binary inside the DMG,
# including Copy.app itself, so the same ticket can also be stapled directly
# to the exported .app. Stapling the app (not just the DMG) means the copy
# that Sparkle unzips and relaunches on update passes Gatekeeper's assessment
# offline, without depending on a live connection to Apple's servers.
echo "    Stapling Copy.app..."
xcrun stapler staple "$APP_PATH"

step "9/9 Building the Sparkle enclosure and appcast snippet"
rm -f "$SPARKLE_ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$SPARKLE_ZIP_PATH"

SIGN_UPDATE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" -name sign_update -path '*sparkle*' 2>/dev/null | head -1)"
if [[ -z "$SIGN_UPDATE_BIN" ]]; then
  echo "error: could not find Sparkle's sign_update binary under DerivedData." >&2
  echo "       Build the app at least once via Xcode/xcodebuild so SPM resolves Sparkle, then re-run." >&2
  exit 1
fi

echo "    Signing $SPARKLE_ZIP_PATH with $SIGN_UPDATE_BIN"
SIGN_UPDATE_OUTPUT="$("$SIGN_UPDATE_BIN" "$SPARKLE_ZIP_PATH")"
echo "    $SIGN_UPDATE_OUTPUT"

ED_SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGN_UPDATE_OUTPUT")"
ENCLOSURE_LENGTH="$(sed -n 's/.*length="\([^"]*\)".*/\1/p' <<<"$SIGN_UPDATE_OUTPUT")"

if [[ -z "$ED_SIGNATURE" || -z "$ENCLOSURE_LENGTH" ]]; then
  echo "warning: could not parse edSignature/length from sign_update output; check it above and fill the appcast by hand." >&2
  ED_SIGNATURE="${ED_SIGNATURE:-FILL_ME_IN}"
  ENCLOSURE_LENGTH="${ENCLOSURE_LENGTH:-FILL_ME_IN}"
fi

BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")"
PUB_DATE="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/Copy-${VERSION}.dmg"

APPCAST_ITEM="$(cat <<ITEM
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${ENCLOSURE_LENGTH}"
                type="application/octet-stream"
            />
        </item>
ITEM
)"

echo ""
echo "    Appcast <item> snippet:"
echo "$APPCAST_ITEM"

if [[ ! -f "$APPCAST_PATH" ]]; then
  echo ""
  echo "    $APPCAST_PATH does not exist yet; creating a new appcast skeleton."
  mkdir -p "$(dirname "$APPCAST_PATH")"
  cat > "$APPCAST_PATH" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Copy</title>
        <link>https://tarikbc.github.io/Copy/appcast.xml</link>
        <description>Copy release notes and updates</description>
        <language>en</language>
${APPCAST_ITEM}
    </channel>
</rss>
APPCAST
else
  echo ""
  echo "    Inserting the new <item> into the existing $APPCAST_PATH"
  # Insert the new item right after the opening <channel> tag so the newest
  # release sorts first, matching Sparkle's convention of newest-item-first.
  APPCAST_TMP="$(mktemp)"
  awk -v item="$APPCAST_ITEM" '
    { print }
    /<channel>/ && !inserted { print item; inserted = 1 }
  ' "$APPCAST_PATH" > "$APPCAST_TMP"
  mv "$APPCAST_TMP" "$APPCAST_PATH"
fi

step "Done. Publish command (run this yourself once you are ready -- it is not run for you):"
echo "gh release create \"v${VERSION}\" \"$DMG_PATH\" \"$SPARKLE_ZIP_PATH\" --title \"Copy ${VERSION}\" --notes-file CHANGELOG.md"
echo ""
echo "Artifacts:"
echo "  $DMG_PATH"
echo "  $SPARKLE_ZIP_PATH"
echo "  $APPCAST_PATH"
