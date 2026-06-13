#!/usr/bin/env bash
#
# Generate Apple signing certificates + provisioning profiles for Daccord's App
# Store CI and upload them as GitHub Actions secrets. Run once on a Mac with
# `fastlane`, `gh`, and `openssl` installed and `gh` authenticated to the repo.
#
# Prereqs:
#   - An App Store Connect API key (.p8) with Admin or App Manager role.
#   - The app record + bundle id (com.cattrall.daccord) already exist.
#
# Usage:
#   ASC_ISSUER_ID=<uuid> APPLE_TEAM_ID=<10char> \
#     scripts/bootstrap-signing.sh /path/to/AuthKey_XXXXXXXXXX.p8
#
#   ASC_KEY_ID defaults to the <id> parsed from the AuthKey_<id>.p8 filename.
#
# It is idempotent-ish: fastlane reuses an existing matching cert/profile rather
# than always creating new ones (Apple caps distribution certs).
set -euo pipefail

P8="${1:?usage: bootstrap-signing.sh /path/to/AuthKey_XXXX.p8}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect → Users and Access → Integrations)}"
: "${APPLE_TEAM_ID:?set APPLE_TEAM_ID (10-char Apple Developer team id)}"
ASC_KEY_ID="${ASC_KEY_ID:-$(basename "$P8" | sed -E 's/^AuthKey_([A-Za-z0-9]+)\.p8$/\1/')}"
BUNDLE_ID="${APP_BUNDLE_ID:-com.cattrall.daccord}"
REPO="${GH_REPO:-DaccordProject/daccord}"

IOS_PROFILE_NAME="Daccord iOS App Store"
MAC_PROFILE_NAME="Daccord Mac App Store"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
CERT_PW="$(openssl rand -base64 18)"

# App Store Connect API key JSON consumed by fastlane's api_key_path.
KEY_JSON="$WORK/asc_key.json"
python3 - "$P8" "$ASC_KEY_ID" "$ASC_ISSUER_ID" > "$KEY_JSON" <<'PY'
import json, sys
p8, key_id, issuer = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    "key_id": key_id,
    "issuer_id": issuer,
    "key": open(p8).read(),
    "duration": 1200,
    "in_house": False,
}))
PY

run_cert() {  # <type> <platform> <out_basename>
  local type="$1" platform="$2" base="$3"
  fastlane run cert \
    api_key_path:"$KEY_JSON" \
    type:"$type" \
    platform:"$platform" \
    team_id:"$APPLE_TEAM_ID" \
    output_path:"$WORK" \
    generate_apple_certs:true >/dev/null
  # fastlane `cert` writes <cert_id>.p12 (unencrypted). Re-wrap it with our
  # shared password so apple-actions/import-codesign-certs can import it.
  local p12; p12="$(ls -t "$WORK"/*.p12 | head -1)"
  openssl pkcs12 -in "$p12" -nodes -passin pass: -out "$WORK/$base.pem" 2>/dev/null
  openssl pkcs12 -export -in "$WORK/$base.pem" -out "$WORK/$base.p12" \
    -passout pass:"$CERT_PW" -name "$base"
  rm -f "$p12" "$WORK/$base.pem"
}

run_profile() {  # <platform> <name> <out_basename>
  local platform="$1" name="$2" base="$3"
  fastlane run get_provisioning_profile \
    api_key_path:"$KEY_JSON" \
    app_identifier:"$BUNDLE_ID" \
    platform:"$platform" \
    team_id:"$APPLE_TEAM_ID" \
    provisioning_name:"$name" \
    filename:"$base.profile" \
    output_path:"$WORK" >/dev/null
}

echo "==> Apple Distribution cert (iOS + macOS app signing)"
run_cert distribution ios apple_dist

echo "==> Mac Installer Distribution cert (.pkg)"
run_cert mac_installer_distribution macos mac_installer

echo "==> Developer ID Application cert (notarized DMG)"
run_cert developer_id_application macos developer_id

echo "==> iOS App Store provisioning profile"
run_profile ios "$IOS_PROFILE_NAME" ios_profile

echo "==> Mac App Store provisioning profile"
run_profile macos "$MAC_PROFILE_NAME" mac_profile

b64() { base64 < "$1" | tr -d '\n'; }
set_secret() { echo "    - $1"; gh secret set "$1" --repo "$REPO" --body "$2" >/dev/null; }

echo "==> Setting GitHub Actions secrets on $REPO"
set_secret ASC_KEY_ID            "$ASC_KEY_ID"
set_secret ASC_ISSUER_ID         "$ASC_ISSUER_ID"
set_secret ASC_KEY_P8_BASE64     "$(b64 "$P8")"
set_secret APPLE_TEAM_ID         "$APPLE_TEAM_ID"
set_secret CERT_P12_PASSWORD     "$CERT_PW"
set_secret APPLE_DIST_CERT_P12   "$(b64 "$WORK/apple_dist.p12")"
set_secret MAC_INSTALLER_CERT_P12 "$(b64 "$WORK/mac_installer.p12")"
set_secret DEVELOPER_ID_CERT_P12 "$(b64 "$WORK/developer_id.p12")"
set_secret IOS_PROFILE_BASE64    "$(b64 "$WORK"/ios_profile.profile)"
set_secret IOS_PROFILE_NAME      "$IOS_PROFILE_NAME"
set_secret MAC_PROFILE_BASE64    "$(b64 "$WORK"/mac_profile.profile)"
set_secret MAC_PROFILE_NAME      "$MAC_PROFILE_NAME"

echo "==> Done. All signing secrets set on $REPO."
