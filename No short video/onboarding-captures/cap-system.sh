#!/bin/bash
# cap-system.sh <en|fr> — captures système (home, verrouillé, PiP) via OnboardingCaptureTests.
D=${SIM:-255B3F30-A6C4-4769-97DA-E46FF0898EA4}; B=sharik.No-short-video; S=$(cd "$(dirname "$0")" && pwd); L=$1
PROJ="/Users/sharikmohamed/Documents/IOS/no short video/No short video"
mkdir -p "$S/shots"
xcrun simctl spawn $D defaults write $B appLanguage -string $L
xcrun simctl spawn $D defaults write $B AppleLanguages -array $L
xcrun simctl spawn $D defaults write $B hasSeenOnboarding -bool YES
xcrun simctl spawn $D defaults write $B hasSeenQuickstart -bool YES
xcrun simctl status_bar $D override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3
WIKI=https://en.m.wikipedia.org/wiki/Cat; [ $L = fr ] && WIKI=https://fr.m.wikipedia.org/wiki/Chat
cd "$PROJ"
TEST_RUNNER_CAPTURE_DIR="$S/shots" TEST_RUNNER_CAPTURE_LANG=$L TEST_RUNNER_CAPTURE_SCRIPT="$S/catify.js" \
xcodebuild test -project "No short video.xcodeproj" -scheme "No short videoUITests" -destination "id=$D" \
  -derivedDataPath .derivedData -only-testing:"No short videoUITests/OnboardingCaptureTests" ${ONLY:+-only-testing:"No short videoUITests/OnboardingCaptureTests/$ONLY"} 2>&1 | grep -E "error:|Test Case|TEST (SUCCEEDED|FAILED)|\*\*" | tail -12
