#!/usr/bin/env bash
# grab.sh '<rtsp-url-template>' [max_channels] [outdir]
#   Template may contain {CH} for a multi-channel DVR/NVR, e.g.
#     'rtsp://10.0.0.50:554/chID={CH}&streamType=main'
#   For a single camera, pass the exact URL with no {CH}.
# Grabs a CLEAN late frame per channel (avoids corrupted first-keyframe colors on HEVC),
# saves cam_chN.jpg, and opens them.
# Authorized use only.
set -u

TEMPLATE="${1:-}"
MAXCH="${2:-8}"
OUT="${3:-$(pwd)}"
[ -z "$TEMPLATE" ] && { echo "usage: grab.sh '<rtsp-url-template>' [max_channels] [outdir]"; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg not found — brew install ffmpeg"; exit 1; }
mkdir -p "$OUT"

# grab one clean frame from a URL -> outfile. Pulls a short sequence and keeps a late frame.
grab_one() {
  local url="$1" out="$2" tmp
  tmp="$OUT/.seq_$$"
  rm -f "${tmp}"_*.jpg
  ffmpeg -y -rtsp_transport tcp -timeout 12000000 -i "$url" -an -frames:v 45 -q:v 2 "${tmp}_%03d.jpg" >/dev/null 2>&1
  local last
  last=$(ls "${tmp}"_*.jpg 2>/dev/null | tail -1)
  if [ -n "$last" ]; then cp "$last" "$out"; rm -f "${tmp}"_*.jpg; return 0; fi
  # fallback: single frame
  ffmpeg -y -rtsp_transport tcp -timeout 12000000 -i "$url" -frames:v 1 -q:v 2 -update 1 "$out" >/dev/null 2>&1
  [ -s "$out" ]
}

grabbed=()
if echo "$TEMPLATE" | grep -q '{CH}'; then
  echo "Multi-channel DVR — enumerating channels 1..$MAXCH"
  for ch in $(seq 1 "$MAXCH"); do
    url="${TEMPLATE//\{CH\}/$ch}"
    out="$OUT/cam_ch${ch}.jpg"
    if grab_one "$url" "$out"; then
      sz=$(wc -c < "$out" | tr -d ' ')
      if [ "$sz" -gt 8000 ]; then echo "  ch$ch: frame saved (${sz}B)  -> $out"; grabbed+=("$out")
      else echo "  ch$ch: black/no-signal (${sz}B)"; grabbed+=("$out"); fi
    else
      echo "  ch$ch: no stream"
    fi
  done
else
  out="$OUT/cam.jpg"
  if grab_one "$TEMPLATE" "$out"; then echo "  frame saved -> $out"; grabbed+=("$out"); else echo "  no stream"; fi
fi

# open them (macOS: open, Linux: xdg-open)
if [ "${#grabbed[@]}" -gt 0 ]; then
  if command -v open >/dev/null 2>&1; then open "${grabbed[@]}" 2>/dev/null
  elif command -v xdg-open >/dev/null 2>&1; then for f in "${grabbed[@]}"; do xdg-open "$f" >/dev/null 2>&1; done
  fi
  echo "Opened ${#grabbed[@]} frame(s). Now read/classify each: outdoor / common-area / PRIVATE space."
fi
