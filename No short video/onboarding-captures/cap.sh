#!/bin/bash
# cap.sh <name> <lang> <wait> [launch args...]
D=255B3F30-A6C4-4769-97DA-E46FF0898EA4; B=sharik.No-short-video; S=$(cd "$(dirname "$0")" && pwd)
name=$1; lang=$2; wait=$3; shift 3
xcrun simctl terminate $D $B 2>/dev/null
xcrun simctl spawn $D defaults write $B appLanguage -string $lang
xcrun simctl spawn $D defaults write $B AppleLanguages -array $lang
xcrun simctl spawn $D defaults write $B hasSeenOnboarding -bool YES
xcrun simctl spawn $D defaults write $B hasSeenQuickstart -bool YES
python3 "$S/fixtures.py" "$(xcrun simctl get_app_container $D $B data)" $lang >/dev/null
xcrun simctl launch $D $B -debugCaptureScript "$S/catify.js" "$@" >/dev/null
perl -e "select(undef,undef,undef,$wait)"
mkdir -p "$S/shots"; xcrun simctl io $D screenshot "$S/shots/${name}_${lang}.png" >/dev/null 2>&1
python3 -c "from PIL import Image; Image.open('$S/shots/${name}_${lang}.png').resize((402,874)).save('$S/v.png')"
