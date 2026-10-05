#!/bin/sh
# Turns a screen recording into a site clip for site/clips:
#   site/clips/<name>.mp4 — 16:10, 1680×1050, H.264 High, 30 fps, no audio, faststart, CRF 20
#                           (sharp at the cards' ~700 px on Retina; roughly 0.5–1.5 MB for 10 s)
#   site/clips/<name>.jpg — its poster, 1600×1000, the frame at --poster seconds
# Crop to the feature, so it's downscaled 1.5× at most; small UI text turns to mush past that.
#
# Usage: marketing/clips/make-clip.sh <recording.mov> <name> [start] [duration] [crop] [poster]
#   start, duration — seconds into the recording (default 0 and the whole thing; keep clips 5–13 s)
#   crop            — w:h:x:y in the recording's pixels; default the biggest centered 16:10 area
#   poster          — seconds into the finished clip for the poster frame (default 1)
# See docs/marketing-assets.md.
set -e
in="$1"; name="$2"; start="${3:-0}"; duration="$4"; crop="$5"; poster="${6:-1}"
[ -n "$in" ] && [ -n "$name" ] || { sed -n '2,14p' "$0"; exit 1; }
out="$(cd "$(dirname "$0")/../.." && pwd)/site/clips"

# The biggest centered 16:10 area, when no crop is given.
[ -n "$crop" ] || crop="'min(iw,ih*16/10)':'min(ih,iw*10/16)':'(iw-min(iw,ih*16/10))/2':'(ih-min(ih,iw*10/16))/2'"
trim="-ss $start"
[ -n "$duration" ] && trim="$trim -t $duration"

ffmpeg -v error -y $trim -i "$in" \
  -vf "crop=$crop,scale=1680:1050:flags=lanczos,fps=30,format=yuv420p" \
  -an -c:v libx264 -profile:v high -preset slow -tune animation -crf 20 -movflags +faststart "$out/$name.mp4"
# The poster from the recording itself, not the encoded clip, so it's as sharp as it can be.
ffmpeg -v error -y -ss "$(echo "$start + $poster" | bc)" -i "$in" -frames:v 1 \
  -vf "crop=$crop,scale=1600:1000:flags=lanczos" -q:v 2 "$out/$name.jpg"
ls -la "$out/$name.mp4" "$out/$name.jpg"
