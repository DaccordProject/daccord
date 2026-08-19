#!/usr/bin/env bash
# Generate the App Store "What's New" text for a tagged release.
#
# Apple requires release notes on every version submission — a submission
# without them fails App Store Connect validation — so CI has to produce them
# unattended. This derives them from the commits between the previous release
# tag and HEAD, mirroring what `generate_release_notes: true` does for the
# GitHub Release, and writes one copy per Apple platform into the deliver
# metadata tree that `fastlane ios appstore` / `fastlane mac appstore` upload.
#
# Usage: dist/app-store-release-notes.sh
#
# Requires the full history and tags (`actions/checkout` with fetch-depth: 0);
# with a shallow clone there is no previous tag to diff against and the script
# falls back to the generic note rather than failing the release.
set -euo pipefail

# Deliver reads <metadata_path>/<lang>/release_notes.txt. The two platforms get
# separate trees so a future iOS-only or macOS-only note doesn't need a fork.
LANG_DIR="en-US"
TARGETS=("fastlane/metadata/ios/$LANG_DIR" "fastlane/metadata/mac/$LANG_DIR")

# Apple caps What's New at 4000 characters.
MAX_CHARS=4000

# Generic text used when there is nothing better to say. Never empty: an empty
# release_notes.txt is exactly the validation failure this script exists to
# avoid.
FALLBACK="Bug fixes and performance improvements."

previous_tag() {
  # The release tag before the one being built. `git describe` walks back from
  # HEAD's parent so the tag currently being released is never its own
  # predecessor. Release candidates are skipped — a stable release's notes
  # should span everything since the last *stable* release, not since its last
  # rc.
  git describe --tags --abbrev=0 --exclude='*-rc*' HEAD^ 2>/dev/null || true
}

# Subjects of the user-facing commits in the range, newest first, as a bullet
# list. Merge commits are dropped (they restate the PR title, which is already
# the squashed commit's subject), and so is the release's own version bump.
subjects() {
  local range="$1"
  git log --no-merges --pretty=format:'%s' "$range" 2>/dev/null |
    grep -vE '^chore: bump to ' || true
}

# Conventional-commit types users actually see in the app. `ci:`, `chore:`,
# `test:`, `docs:`, `build:` and `refactor:` are real work but say nothing to
# someone reading the store listing, so they are filtered out — unless that
# leaves nothing at all, in which case the unfiltered list is better than the
# generic fallback.
user_facing() {
  grep -E '^(feat|fix|perf)(\([^)]*\))?!?: ' || true
}

# Strip the conventional-commit prefix and bullet the rest: "feat(voice): add x"
# becomes "• Add x". Store readers are not reading a changelog.
prettify() {
  sed -E 's/^(feat|fix|perf)(\([^)]*\))?!?: //' |
    sed -E 's/^(.)/\U\1/' |
    sed -E 's/^/• /'
}

main() {
  local prev range raw notes
  prev="$(previous_tag)"
  if [ -n "$prev" ]; then
    range="$prev..HEAD"
    echo "Release notes range: $range"
  else
    # No previous tag reachable (shallow clone, or the very first release).
    range=""
    echo "No previous tag found — using the fallback note."
  fi

  notes=""
  if [ -n "$range" ]; then
    raw="$(subjects "$range")"
    notes="$(printf '%s\n' "$raw" | user_facing | prettify)"
    # Nothing user-facing in this range: fall back to every non-merge subject
    # before giving up on specifics entirely.
    if [ -z "$notes" ]; then
      notes="$(printf '%s\n' "$raw" | sed -E 's/^/• /')"
    fi
  fi

  # Trailing whitespace-only output counts as empty.
  if [ -z "$(printf '%s' "$notes" | tr -d '[:space:]')" ]; then
    notes="$FALLBACK"
  fi

  # Truncate on a bullet boundary so the text never ends mid-sentence.
  if [ "${#notes}" -gt "$MAX_CHARS" ]; then
    notes="$(printf '%s' "$notes" | head -c "$MAX_CHARS" | sed '$d')"
    echo "::warning::Release notes exceeded $MAX_CHARS characters and were truncated."
  fi

  for dir in "${TARGETS[@]}"; do
    mkdir -p "$dir"
    printf '%s\n' "$notes" > "$dir/release_notes.txt"
    echo "Wrote $dir/release_notes.txt"
  done

  echo "--- What's New ---"
  printf '%s\n' "$notes"
  echo "------------------"
}

main "$@"
