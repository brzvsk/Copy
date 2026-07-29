#!/usr/bin/env bash
#
# setup-release-secrets.sh - configure the GitHub secrets the release workflow
# (.github/workflows/release.yml) needs to cut a signed, notarized release, and
# stash the generated passwords/identifiers in your login keychain so you never
# have to remember them.
#
# Run this INTERACTIVELY on the Mac that holds your Developer ID Application
# signing identity. Exporting the signing key triggers a macOS keychain
# authorization prompt: click Allow (or Always Allow) when it appears.
#
# Usage:
#   Scripts/setup-release-secrets.sh            # run every section
#   Scripts/setup-release-secrets.sh cert       # only the Developer ID cert
#   Scripts/setup-release-secrets.sh sparkle    # only the Sparkle update key
#   Scripts/setup-release-secrets.sh notary     # only the notarization API key
#
# Nothing secret is printed to the terminal or written into the repo. Temporary
# files are created in a private temp dir and deleted on exit.
set -euo pipefail

REPO="tarikbc/Copy"
SIGN_IDENTITY="Developer ID Application"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# A keychain "service" under which we save the generated passwords/ids for you.
KC_SERVICE="com.tarikbc.Copy.release"

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

say()  { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# Save a value into the login keychain so it is recoverable later.
# security add-generic-password -U updates the item if it already exists.
save_to_keychain() {
  local account="$1" value="$2"
  security add-generic-password -U \
    -a "$account" -s "$KC_SERVICE" -w "$value" "$LOGIN_KEYCHAIN"
  info "saved to keychain (service $KC_SERVICE, account $account)"
}

preflight() {
  command -v gh >/dev/null       || die "GitHub CLI (gh) not found. brew install gh"
  command -v security >/dev/null || die "security tool not found (macOS only)."
  command -v base64 >/dev/null   || die "base64 not found."
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"
  info "target repo: $REPO"
}

# ---------------------------------------------------------------------------
# 1. Developer ID Application certificate -> DEVELOPER_ID_CERT_P12_BASE64 + PASSWORD
# ---------------------------------------------------------------------------
setup_cert() {
  say "Developer ID certificate"
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    die "no '$SIGN_IDENTITY' signing identity found in your keychain."
  fi

  local p12="$WORK_DIR/copy-devid.p12"
  # Generate a strong random password for the .p12 and keep it in the keychain
  # so you can recover it; it also becomes the DEVELOPER_ID_CERT_PASSWORD secret.
  local pw
  pw="$(openssl rand -base64 24)"

  info "exporting your Developer ID identity (approve the keychain prompt if it appears)"
  # Exports the code-signing identities from the login keychain. The CI import
  # step selects "$SIGN_IDENTITY" by name, so any extra identities are harmless.
  security export -k "$LOGIN_KEYCHAIN" -t identities -f pkcs12 -P "$pw" -o "$p12" \
    || die "certificate export failed or was cancelled at the keychain prompt."
  [[ -s "$p12" ]] || die "exported .p12 is empty."

  base64 -i "$p12" | gh secret set DEVELOPER_ID_CERT_P12_BASE64 --repo "$REPO"
  printf '%s' "$pw" | gh secret set DEVELOPER_ID_CERT_PASSWORD --repo "$REPO"
  save_to_keychain "developer-id-p12-password" "$pw"
  info "set DEVELOPER_ID_CERT_P12_BASE64 and DEVELOPER_ID_CERT_PASSWORD"
}

# ---------------------------------------------------------------------------
# 2. Sparkle EdDSA update-signing key -> SPARKLE_PRIVATE_KEY
# ---------------------------------------------------------------------------
setup_sparkle() {
  say "Sparkle update-signing key"
  local gen
  gen="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -name generate_keys -path '*sparkle*' -print -quit 2>/dev/null || true)"
  [[ -n "$gen" ]] || die "Sparkle's generate_keys not found. Build the app once so SPM resolves Sparkle, then retry."

  local key="$WORK_DIR/sparkle-copy.key"
  # Copy's dedicated key lives under the 'copy' keychain account (kept separate
  # from any other Sparkle app on this Mac). Export it just long enough to upload.
  "$gen" --account copy -x "$key" >/dev/null 2>&1 \
    || die "could not export Copy's Sparkle key from the 'copy' keychain account."
  gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO" < "$key"
  info "set SPARKLE_PRIVATE_KEY"
}

# ---------------------------------------------------------------------------
# 3. App Store Connect API key -> NOTARY_API_KEY_BASE64 + KEY_ID + ISSUER_ID
# ---------------------------------------------------------------------------
setup_notary() {
  say "Notarization (App Store Connect API key)"
  info "Create one at App Store Connect > Users and Access > Integrations >"
  info "App Store Connect API > + (role: Developer). Download the .p8 (once only),"
  info "and note the Key ID and Issuer ID shown on that page."
  echo

  local p8 key_id issuer_id
  read -r -p "    Path to the downloaded .p8 file: " p8
  p8="${p8/#\~/$HOME}"
  [[ -f "$p8" ]] || die "no file at: $p8"
  read -r -p "    Key ID: " key_id
  read -r -p "    Issuer ID: " issuer_id
  [[ -n "$key_id" && -n "$issuer_id" ]] || die "Key ID and Issuer ID are both required."

  base64 -i "$p8" | gh secret set NOTARY_API_KEY_BASE64 --repo "$REPO"
  printf '%s' "$key_id"    | gh secret set NOTARY_API_KEY_ID --repo "$REPO"
  printf '%s' "$issuer_id" | gh secret set NOTARY_API_ISSUER_ID --repo "$REPO"
  save_to_keychain "notary-api-key-id" "$key_id"
  save_to_keychain "notary-api-issuer-id" "$issuer_id"
  info "set NOTARY_API_KEY_BASE64, NOTARY_API_KEY_ID, and NOTARY_API_ISSUER_ID"
  info "keep the .p8 itself somewhere safe: App Store Connect only lets you download it once."
}

main() {
  preflight
  local section="${1:-all}"
  case "$section" in
    cert)    setup_cert ;;
    sparkle) setup_sparkle ;;
    notary)  setup_notary ;;
    all)     setup_cert; setup_sparkle; setup_notary ;;
    *)       die "unknown section '$section' (use: cert | sparkle | notary, or no argument for all)." ;;
  esac

  say "Done"
  info "Current secrets on $REPO:"
  gh secret list --repo "$REPO" | sed 's/^/    /'
  echo
  info "Next: enable GitHub Pages on the docs/ folder (Settings > Pages), then"
  info "cut a release with:  git tag v0.1.0 && git push origin v0.1.0"
}

main "$@"
