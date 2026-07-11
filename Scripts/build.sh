#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"

xcodebuild \
  -project "$repo_root/ChargingLimiter.xcodeproj" \
  -scheme ChargingLimiter \
  -configuration Debug \
  -derivedDataPath "$repo_root/.build/xcode" \
  -destination 'platform=macOS,arch=arm64' \
  build

print "Built app: $repo_root/.build/xcode/Build/Products/Debug/Charging Limiter.app"
