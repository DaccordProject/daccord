#!/usr/bin/env bash
# Download Twemoji SVGs for the expanded emoji catalog, skin tone variants,
# and country flags.
# Source: https://raw.githubusercontent.com/twitter/twemoji/master/assets/svg/
#
# Usage: bash scripts/download_emoji.sh

set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/twitter/twemoji/master/assets/svg"
DEST_DIR="$(cd "$(dirname "$0")/.." && pwd)/assets/theme/emoji"

mkdir -p "$DEST_DIR"

download_svg() {
  local filename="$1.svg"
  local dest="$DEST_DIR/$filename"
  if [ -f "$dest" ]; then
    return 0
  fi
  if curl -sfL -o "$dest" "$BASE_URL/$filename"; then
    return 0
  else
    echo "  WARN: Failed to download $filename"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Base emoji (all catalog entries)
# ---------------------------------------------------------------------------
BASE_CODEPOINTS=(
  # Smileys
  1f600 1f603 1f604 1f601 1f606 1f605 1f923 1f602
  1f642 1f643 1f609 1f60a 1f607 1f970 1f60d 1f929
  1f618 1f617 1f60b 1f61b 1f61c 1f92a 1f92b 1f914
  1f9d0 1f913 1f60e 1f973 1f920 1f60f 1f612 1f644
  1f61e 1f61f 1f620 1f621 1f62d 1f97a 1f628 1f631
  1f92f 1f62f 1f634 1f924 1f922 1f927 1f975 1f976
  1f971 1f925 1f480 1f921 1f4a9 1f47b 1f47d 1f916
  # People
  1f44b 1f91a 270b 1f596 1f44d 1f44e 1f44f 1f64f
  1f4aa 1f91d 270c 1f44c 1f90f 1f44a 1f91b 1f91c
  1f91e 1f918 1f919 1f448 1f449 1f446 1f447 1f595
  1f932 270d 1f485 1f933
  # Nature
  1f436 1f431 1f42d 1f439 1f430 1f98a 1f43b 1f43c
  1f428 1f42f 1f981 1f42e 1f437 1f438 1f435 1f427
  1f414 1f985 1f989 1f984 1f41d 1f98b 1f41e 1f40c
  1f419 1f42c 1f433 1f988 1f422 1f40d 1f40a 1f33b
  1f339 1f33a 1f338 1f340 1f332 1f335 1f344 1f342
  # Food
  1f34e 1f34a 1f34b 1f34c 1f349 1f347 1f353 1f351
  1f352 1f34d 1f345 1f951 1f33d 1f9c0 1f95a 1f953
  1f95e 1f354 1f355 1f32d 1f32e 1f32f 1f35f 1f363
  1f35c 1f368 1f382 1f370 1f369 1f36a 1f36b 1f36c
  1f36d 1f37f 2615 1f375 1f37a 1f377 1f378 1f95b
  # Activities
  26bd 1f3c0 1f3c8 26be 1f3be 1f3d0 1f3b1 1f3b3
  1f3d2 1f3d3 1f3f8 1f94a 1f3af 1f3c6 1f3c5 1f3b2
  1f9e9 1f3ae 1f3b0 1f3a8 1f3ad 1f3b5 1f3b6 1f3b8
  1f3b9 1f3b7 1f3ba 1f3bb 1f941 1f3a4 1f3a7 1f3ac
  1f3ab 1f3a3 1f3a1 1f3a2
  # Travel
  1f697 1f695 1f68c 1f693 1f691 1f692 1f6b2 1f3cd
  1f686 2708 1f681 1f680 1f6f8 26f5 1f6a2 2693
  1f3e0 1f3d7 1f3df 26f0 1f30b 1f3d6 26fa 1f30e
  1f30f 2b50 1f319 2600 1f308 1f30a 1f30c 2604
  1f305 1f386 1f387
  # Objects
  231a 23f0 231b 1f4f1 1f4bb 2328 1f4f7 1f4f9
  1f4fa 1f4fb 1f50b 1f50c 1f4a1 1f4da 1f4d6 1f4f0
  270f 1f4dd 1f4ce 1f4cc 2702 1f527 1f528 1f50d
  1f512 1f511 1f381 1f389 1f514 1f48e 1f451 1f48d
  1f4bc 1f4b0 2709 1f4e6 1f48a 1f489 1f4b3
  # Symbols
  2764 1f9e1 1f49b 1f49a 1f499 1f49c 1f5a4 1f90d
  1f90e 1f494 1f495 1f496 1f497 1f49e 1f4af 2705
  274c 2757 2753 2728 1f440 1f4a5 1f4a2 1f4ab
  1f4a4 1f525 26a0 26d4 1f6ab 267b 267e 262e
  262f 1f531
)

echo "Downloading base emoji (${#BASE_CODEPOINTS[@]} files)..."
count=0
for cp in "${BASE_CODEPOINTS[@]}"; do
  if download_svg "$cp"; then
    count=$((count + 1))
  fi
done
echo "  Ensured $count base emoji SVGs."

# ---------------------------------------------------------------------------
# Skin tone variants
# ---------------------------------------------------------------------------
TONES=("1f3fb" "1f3fc" "1f3fd" "1f3fe" "1f3ff")

# Base codepoints for emoji that support skin tones
declare -A SKIN_EMOJI=(
  ["wave"]="1f44b"
  ["raised_back_of_hand"]="1f91a"
  ["raised_hand"]="270b"
  ["vulcan"]="1f596"
  ["thumbs_up"]="1f44d"
  ["thumbs_down"]="1f44e"
  ["clap"]="1f44f"
  ["pray"]="1f64f"
  ["muscle"]="1f4aa"
  ["victory"]="270c"
  ["ok_hand"]="1f44c"
  ["pinching"]="1f90f"
  ["fist_bump"]="1f44a"
  ["left_fist"]="1f91b"
  ["right_fist"]="1f91c"
  ["crossed_fingers"]="1f91e"
  ["rock_on"]="1f918"
  ["call_me"]="1f919"
  ["point_left"]="1f448"
  ["point_right"]="1f449"
  ["point_up"]="1f446"
  ["point_down"]="1f447"
  ["middle_finger"]="1f595"
  ["palms_up"]="1f932"
  ["writing_hand"]="270d"
  ["nail_polish"]="1f485"
  ["selfie"]="1f933"
)

echo "Downloading skin tone variants (${#SKIN_EMOJI[@]} emoji x 5 tones)..."
count=0
for name in "${!SKIN_EMOJI[@]}"; do
  base="${SKIN_EMOJI[$name]}"
  for tone in "${TONES[@]}"; do
    if download_svg "${base}-${tone}"; then
      count=$((count + 1))
    fi
  done
done
echo "  Ensured $count skin tone SVGs."

# ---------------------------------------------------------------------------
# Country flags (regional indicator pairs)
# ---------------------------------------------------------------------------
FLAG_CODEPOINTS=(
  1f1fa-1f1f8 1f1ec-1f1e7 1f1e8-1f1e6 1f1e6-1f1fa 1f1e9-1f1ea
  1f1eb-1f1f7 1f1ea-1f1f8 1f1ee-1f1f9 1f1ef-1f1f5 1f1f0-1f1f7
  1f1e8-1f1f3 1f1ee-1f1f3 1f1e7-1f1f7 1f1f2-1f1fd 1f1f7-1f1fa
  1f1f3-1f1f1 1f1f8-1f1ea 1f1f3-1f1f4 1f1eb-1f1ee 1f1e9-1f1f0
  1f1ee-1f1ea 1f1f5-1f1f9 1f1e8-1f1ed 1f1e7-1f1ea 1f1e6-1f1f9
  1f1f5-1f1f1 1f1f9-1f1f7 1f1fa-1f1e6 1f1f3-1f1ff 1f1e6-1f1f7
  1f1ff-1f1e6 1f1ea-1f1ec 1f1f3-1f1ec 1f1f0-1f1ea 1f1f9-1f1ed
  1f1fb-1f1f3 1f1f5-1f1ed 1f1ee-1f1e9 1f1f2-1f1fe 1f1f8-1f1ec
  1f1ee-1f1f1 1f1f8-1f1e6 1f1e6-1f1ea 1f1e8-1f1f1 1f1e8-1f1f4
  1f1f5-1f1ea 1f1ec-1f1f7 1f1e8-1f1ff 1f1f7-1f1f4 1f1ed-1f1fa
)

echo "Downloading country flags (${#FLAG_CODEPOINTS[@]} files)..."
count=0
for cp in "${FLAG_CODEPOINTS[@]}"; do
  if download_svg "$cp"; then
    count=$((count + 1))
  fi
done
echo "  Ensured $count flag SVGs."

echo "Done. All emoji SVGs are in $DEST_DIR"
