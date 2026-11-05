#!/bin/zsh
# Renders the repo artwork with headless Chrome. Run from the repo root.
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; P=$(mktemp -d); A="file://$PWD/docs/assets/src/art.html"
shot() { "$C" --headless=new --disable-gpu --hide-scrollbars --user-data-dir=$P --force-device-scale-factor=$4 --virtual-time-budget=4000 --window-size=$3 --screenshot="$PWD/$1" "$A?$2" >/dev/null 2>&1; }
shot docs/assets/hero-light.png 'm=hero&t=light' 1280,420 2
shot docs/assets/hero-dark.png 'm=hero&t=dark' 1280,420 2
shot .github/social-preview.png 'm=social&t=dark' 1280,640 1
shot .claude-plugin/icon.png 'm=icon&t=dark' 1024,1024 1
rm -rf $P
