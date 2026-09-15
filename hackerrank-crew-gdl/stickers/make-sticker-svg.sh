#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--embed] [--max-size N] [--max-bytes N] <input.png> [output.svg] [outline_px]\n' "$(basename "$0")" >&2
  printf 'Default outline_px: 4\n' >&2
  printf 'Example: %s --embed --max-size 2048 --max-bytes 3000000 input.png output.svg 12\n' "$(basename "$0")" >&2
}

embed=false
max_size=""
max_bytes=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --embed)
      embed=true
      shift
      ;;
    --max-size)
      if [[ -z ${2:-} ]]; then
        printf 'Missing value for --max-size\n' >&2
        exit 1
      fi
      max_size="$2"
      shift 2
      ;;
    --max-bytes)
      if [[ -z ${2:-} ]]; then
        printf 'Missing value for --max-bytes\n' >&2
        exit 1
      fi
      max_bytes="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

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

temp_input="$input"
cleanup_temp=false
if [[ -n "$max_size" ]]; then
  temp_input=$(mktemp "/var/folders/h1/zp4f1l5s3vgd78rfj4p459m40000gn/T/opencode/sticker-XXXXXX.png")
  cleanup_temp=true
  sips -Z "$max_size" "$input" --out "$temp_input" >/dev/null
fi

width=$(sips -g pixelWidth "$temp_input" | awk -F': ' '/pixelWidth/ {print $2}')
height=$(sips -g pixelHeight "$temp_input" | awk -F': ' '/pixelHeight/ {print $2}')

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

write_svg() {
  local src_png="$1"
  local dest_svg="$2"
  if [[ "$embed" == true ]]; then
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="-%s -%s %s %s">\n' "$svg_w" "$svg_h" "$pad" "$pad" "$svg_w" "$svg_h" > "$dest_svg"
    cat <<EOF >> "$dest_svg"
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
    <image href="data:image/png;base64,
EOF
    base64 -i "$src_png" | tr -d '\n' >> "$dest_svg"
    printf '" width="%s" height="%s" />\n  </g>\n</svg>\n' "$width" "$height" >> "$dest_svg"
  else
    cat <<EOF > "$dest_svg"
<svg xmlns="http://www.w3.org/2000/svg" width="$svg_w" height="$svg_h" viewBox="-$pad -$pad $svg_w $svg_h">
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
    <image href="$(basename "$input")" width="$width" height="$height" />
  </g>
</svg>
EOF
  fi
}

if [[ -n "$max_bytes" && "$embed" == true ]]; then
  temp_svg=$(mktemp "/var/folders/h1/zp4f1l5s3vgd78rfj4p459m40000gn/T/opencode/sticker-XXXXXX.svg")
  cleanup_temp=true

  max_dim=$(( width > height ? width : height ))
  attempts=0
  while true; do
    write_svg "$temp_input" "$temp_svg"
    size_bytes=$(wc -c < "$temp_svg")
    if (( size_bytes <= max_bytes )); then
      mv "$temp_svg" "$output"
      break
    fi
    attempts=$((attempts + 1))
    if (( attempts > 12 || max_dim < 512 )); then
      mv "$temp_svg" "$output"
      break
    fi
    max_dim=$((max_dim * 85 / 100))
    sips -Z "$max_dim" "$temp_input" --out "$temp_input" >/dev/null
    width=$(sips -g pixelWidth "$temp_input" | awk -F': ' '/pixelWidth/ {print $2}')
    height=$(sips -g pixelHeight "$temp_input" | awk -F': ' '/pixelHeight/ {print $2}')
    pad=$((outline_px * 2))
    filter_x=$((-pad))
    filter_y=$((-pad))
    filter_w=$((width + pad * 2))
    filter_h=$((height + pad * 2))
    svg_w=$((width + pad * 2))
    svg_h=$((height + pad * 2))
  done
else
  write_svg "$temp_input" "$output"
fi

printf 'Wrote %s\n' "$output"

if [[ "$cleanup_temp" == true ]]; then
  rm -f "$temp_input"
  rm -f "${temp_svg:-}"
fi
