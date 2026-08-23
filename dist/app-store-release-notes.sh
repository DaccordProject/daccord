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

# Byte-oriented throughout: the iOS/macOS release jobs run on macos-15 runners,
# whose default locale can vary, and forcing C here keeps `${#notes}` (used for
# the length check below) and `head -c` (used to truncate) counting the same
# units. A touch more conservative than counting Unicode characters — a
# multi-byte bullet can trip the cap a few bytes before 4000 real characters —
# but Apple's limit is never exceeded, which is what matters.
export LC_ALL=C

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

# Optional hand-written override, committed to the repo. Commit subjects make
# decent notes for an ordinary release, but they are written for the people
# maintaining this repo, not for the store listing — a subject like
# "fix(ios): clear the 5.1.2 and 4.0 App Review rejections" is accurate and
# completely wrong to show a user, and App Review reads this text too. When a
# release needs copy written on purpose, put it here; the derived notes remain
# the default so no release can ship without any.
#
# Clear it after the release it was written for, or the next release ships
# stale text — the version it belongs to is recorded on the first line as a
# comment, which is stripped before delivery, so a mismatch is visible in the
# job log.
OVERRIDE="dist/release-notes.txt"

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
#
# Capitalization uses awk, not GNU sed's \U — the iOS/macOS release jobs run on
# macos-15, whose default /usr/bin/sed is BSD sed and doesn't support \U. It
# would silently mangle every bullet in the actual App Store submission
# ("• Uadd x" instead of "• Add x") rather than error, so this only shows up by
# reading the generated text.
prettify() {
  sed -E 's/^(feat|fix|perf)(\([^)]*\))?!?: //' |
    awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }' |
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
  if [ -s "$OVERRIDE" ]; then
    # Strip comment lines and blank padding; keep the author's own wording and
    # bullets otherwise untouched.
    # `|| true` is load-bearing, as it is on subjects()/user_facing(): grep
    # exits 1 when nothing matches, and under `set -euo pipefail` that kills
    # the script mid-assignment. An override holding only comments would then
    # write no release_notes.txt at all — the empty-notes submission failure
    # this script exists to prevent, arriving silently.
    notes="$(grep -vE '^[[:space:]]*#' "$OVERRIDE" | sed -e 's/[[:space:]]*$//' -e '/./,$!d' || true)"
    # Announce it only if something survived the strip: a file holding nothing
    # but comments falls through to the derived notes, and claiming otherwise
    # in the log would send someone hunting for copy that was never used.
    if [ -n "$(printf '%s' "$notes" | tr -d '[:space:]')" ]; then
      echo "Using hand-written notes from $OVERRIDE"
    else
      echo "$OVERRIDE has no content after comments — deriving from commits"
    fi
  fi

  if [ -z "$notes" ] && [ -n "$range" ]; then
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
