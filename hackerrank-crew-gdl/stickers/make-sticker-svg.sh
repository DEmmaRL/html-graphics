#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--embed] <input.png> [output.svg] [outline_px]\n' "$(basename "$0")" >&2
  printf 'Default outline_px: 4\n' >&2
}

embed=false
if [[ ${1:-} == "--embed" ]]; then
  embed=true
  shift
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

input="$1"
output="${2:-${input%.png}.svg}"
outline_px="${3:-4}"

if [[ ! -f "$input" ]]; then
  printf 'Input not found: %s\n' "$input" >&2
  exit 1
fi

width=$(sips -g pixelWidth "$input" | awk -F': ' '/pixelWidth/ {print $2}')
height=$(sips -g pixelHeight "$input" | awk -F': ' '/pixelHeight/ {print $2}')

if [[ -z "$width" || -z "$height" ]]; then
  printf 'Could not read image dimensions.\n' >&2
  exit 1
fi

pad=$((outline_px * 2))
filter_x=$((-pad))
filter_y=$((-pad))
filter_w=$((width + pad * 2))
filter_h=$((height + pad * 2))
svg_w=$((width + pad * 2))
svg_h=$((height + pad * 2))

if [[ "$embed" == true ]]; then
  image_href="data:image/png;base64,$(base64 -i "$input")"
else
  image_href="$(basename "$input")"
fi

cat <<EOF > "$output"
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="$svg_w" height="$svg_h" viewBox="-$pad -$pad $svg_w $svg_h">
  <defs>
    <filter id="sticker" x="$filter_x" y="$filter_y" width="$filter_w" height="$filter_h" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">
      <feMorphology in="SourceAlpha" operator="dilate" radius="$outline_px" result="dilate" />
      <feFlood flood-color="#ffffff" result="white" />
      <feComposite in="white" in2="dilate" operator="in" result="outline" />
      <feMerge>
        <feMergeNode in="outline" />
        <feMergeNode in="SourceGraphic" />
      </feMerge>
    </filter>
  </defs>
  <g filter="url(#sticker)">
    <image href="$image_href" xlink:href="$image_href" width="$width" height="$height" />
  </g>
</svg>
EOF

printf 'Wrote %s\n' "$output"
