#!/usr/bin/env bash
# Download Twemoji SVGs for skin tone variants and country flags.
# Source: https://raw.githubusercontent.com/twitter/twemoji/master/assets/svg/
#
# Usage: bash scripts/download_emoji.sh

set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/twitter/twemoji/master/assets/svg"
DEST_DIR="$(cd "$(dirname "$0")/.." && pwd)/assets/theme/emoji"

mkdir -p "$DEST_DIR"

# ---------------------------------------------------------------------------
# Skin tone variants
# ---------------------------------------------------------------------------
# Skin tone modifier codepoints
TONES=("1f3fb" "1f3fc" "1f3fd" "1f3fe" "1f3ff")

# Base codepoints for emoji that support skin tones (19 emoji)
declare -A SKIN_EMOJI=(
  ["wave"]="1f44b"
  ["raised_back_of_hand"]="1f91a"
  ["thumbs_up"]="1f44d"
  ["thumbs_down"]="1f44e"
  ["clap"]="1f44f"
  ["pray"]="1f64f"
  ["muscle"]="1f4aa"
  ["victory"]="270c"
  ["ok_hand"]="1f44c"
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
)

echo "Downloading skin tone variants (19 emoji x 5 tones = 95 files)..."
count=0
for name in "${!SKIN_EMOJI[@]}"; do
  base="${SKIN_EMOJI[$name]}"
  for tone in "${TONES[@]}"; do
    filename="${base}-${tone}.svg"
    dest="$DEST_DIR/$filename"
    if [ -f "$dest" ]; then
      continue
    fi
    url="$BASE_URL/$filename"
    if curl -sfL -o "$dest" "$url"; then
      count=$((count + 1))
    else
      echo "  WARN: Failed to download $filename"
    fi
  done
done
echo "  Downloaded $count skin tone SVGs."

# ---------------------------------------------------------------------------
# Country flags (regional indicator pairs)
# ---------------------------------------------------------------------------
declare -A FLAGS=(
  ["flag_us"]="1f1fa-1f1f8"
  ["flag_gb"]="1f1ec-1f1e7"
  ["flag_ca"]="1f1e8-1f1e6"
  ["flag_au"]="1f1e6-1f1fa"
  ["flag_de"]="1f1e9-1f1ea"
  ["flag_fr"]="1f1eb-1f1f7"
  ["flag_es"]="1f1ea-1f1f8"
  ["flag_it"]="1f1ee-1f1f9"
  ["flag_jp"]="1f1ef-1f1f5"
  ["flag_kr"]="1f1f0-1f1f7"
  ["flag_cn"]="1f1e8-1f1f3"
  ["flag_in"]="1f1ee-1f1f3"
  ["flag_br"]="1f1e7-1f1f7"
  ["flag_mx"]="1f1f2-1f1fd"
  ["flag_ru"]="1f1f7-1f1fa"
  ["flag_nl"]="1f1f3-1f1f1"
  ["flag_se"]="1f1f8-1f1ea"
  ["flag_no"]="1f1f3-1f1f4"
  ["flag_fi"]="1f1eb-1f1ee"
  ["flag_dk"]="1f1e9-1f1f0"
  ["flag_ie"]="1f1ee-1f1ea"
  ["flag_pt"]="1f1f5-1f1f9"
  ["flag_ch"]="1f1e8-1f1ed"
  ["flag_be"]="1f1e7-1f1ea"
  ["flag_at"]="1f1e6-1f1f9"
  ["flag_pl"]="1f1f5-1f1f1"
  ["flag_tr"]="1f1f9-1f1f7"
  ["flag_ua"]="1f1fa-1f1e6"
  ["flag_nz"]="1f1f3-1f1ff"
  ["flag_ar"]="1f1e6-1f1f7"
)

echo "Downloading country flags (30 files)..."
count=0
for name in "${!FLAGS[@]}"; do
  cp="${FLAGS[$name]}"
  filename="${cp}.svg"
  dest="$DEST_DIR/$filename"
  if [ -f "$dest" ]; then
    continue
  fi
  url="$BASE_URL/$filename"
  if curl -sfL -o "$dest" "$url"; then
    count=$((count + 1))
  else
    echo "  WARN: Failed to download $filename ($name)"
  fi
done
echo "  Downloaded $count flag SVGs."

echo "Done. All emoji SVGs are in $DEST_DIR"
