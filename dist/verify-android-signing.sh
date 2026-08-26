#!/usr/bin/env bash
# Verify an APK/AAB signature and pin it to the configured stable signing key.
set -euo pipefail

artifact="${1:?usage: verify-android-signing.sh <artifact.apk|artifact.aab>}"
expected="${ANDROID_SIGNING_CERT_SHA256:?set ANDROID_SIGNING_CERT_SHA256}"
expected="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]' | tr -d ':[:space:]')"

if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
  echo "ANDROID_SIGNING_CERT_SHA256 must be exactly one SHA-256 fingerprint (64 hex characters)." >&2
  exit 1
fi
if [[ ! -f "$artifact" ]]; then
  echo "Android artifact not found: $artifact" >&2
  exit 1
fi

export LC_ALL=C
case "$artifact" in
  *.apk)
    if [[ -n "${APKSIGNER:-}" ]]; then
      apksigner="$APKSIGNER"
    else
      apksigner="$(find "${ANDROID_HOME:?ANDROID_HOME is required to locate apksigner}/build-tools" \
        -type f -name apksigner -print | sort -V | tail -1)"
    fi
    if [[ -z "$apksigner" || ! -x "$apksigner" ]]; then
      echo "apksigner was not found." >&2
      exit 1
    fi
    # Build-tools releases have emitted certificate diagnostics on both stdout
    # and stderr over time. Capture both: verification still fails closed via
    # the command's exit status, while the fingerprint parser sees either form.
    output="$("$apksigner" verify --verbose --print-certs "$artifact" 2>&1)"
    mapfile -t fingerprints < <(
      sed -nE 's/^.*certificate SHA-256 digest:[[:space:]]*([0-9A-Fa-f:]+)[[:space:]]*$/\1/p' <<<"$output" |
        tr '[:upper:]' '[:lower:]' | tr -d ':' | sort -u
    )
    ;;
  *.aab)
    # AABs use the JAR signature scheme. Upload keys are intentionally
    # self-signed, so verify integrity here and pin trust to the fingerprint.
    jar_verification="$(jarsigner -verify "$artifact" 2>&1)"
    if ! grep -qx 'jar verified\.' <<<"$jar_verification"; then
      echo "Android App Bundle signature verification failed." >&2
      printf '%s\n' "$jar_verification" >&2
      exit 1
    fi
    output="$(keytool -printcert -jarfile "$artifact")"
    mapfile -t fingerprints < <(
      awk -F': ' '/SHA256:/ {gsub(":", "", $2); print tolower($2); exit}' <<<"$output"
    )
    ;;
  *)
    echo "Expected an .apk or .aab artifact, got: $artifact" >&2
    exit 1
    ;;
esac

if [[ "${#fingerprints[@]}" -ne 1 ]]; then
  echo "Expected exactly one Android signing certificate; found ${#fingerprints[@]}." >&2
  exit 1
fi
if [[ "${fingerprints[0]}" != "$expected" ]]; then
  echo "Android signer fingerprint does not match ANDROID_SIGNING_CERT_SHA256." >&2
  echo "Expected: $expected" >&2
  echo "Actual:   ${fingerprints[0]}" >&2
  exit 1
fi

echo "Verified Android signature and stable signer fingerprint: $artifact"
