#!/bin/bash
# render.sh <html dir> <name> <width> <height> <scale>
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$C" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=$5 --window-size=$3,$4 --virtual-time-budget=6000 --allow-file-access-from-files --screenshot="$1/$2.png" "file://$1/$2.html" >/dev/null 2>&1
