#!/bin/sh
# Renders Mac App Store screenshots from template.html + shots.js into out/<name>.png at 2880×1800.
# Usage: marketing/store/render.sh [name ...]   (no names: every shot in shots.js except calibrate-*)
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p out
names="$*"
[ -n "$names" ] || names=$(grep -o '^  "[^"]*": {' shots.js | cut -d'"' -f2 | grep -v '^calibrate')
for name in $names; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1440,900 --virtual-time-budget=4000 --allow-file-access-from-files \
    --screenshot="$PWD/out/$name.png" "file://$PWD/template.html?shot=$name" 2>/dev/null
  echo "out/$name.png"
done
