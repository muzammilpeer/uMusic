#!/bin/sh
set -eu

workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export CLANG_MODULE_CACHE_PATH=/tmp/umusic-v2-sprint1-clang-cache
export SWIFT_MODULE_CACHE_PATH=/tmp/umusic-v2-sprint1-swift-cache
cd "$workspace_dir"

swift test \
    --disable-sandbox \
    --package-path "$workspace_dir" \
    --scratch-path /tmp/umusic-v2-sprint1-swift-build
"$workspace_dir/Scripts/validate-architecture.sh"
"$workspace_dir/Scripts/check-public-api.sh"

xcodebuild -quiet \
    -scheme UMusicCore \
    -destination 'generic/platform=iOS' \
    -derivedDataPath /tmp/umusic-v2-sprint1-core-ios \
    CODE_SIGNING_ALLOWED=NO \
    build

xcodebuild -quiet \
    -scheme UMusicApp \
    -destination 'generic/platform=iOS' \
    -derivedDataPath /tmp/umusic-v2-sprint1-app-ios \
    CODE_SIGNING_ALLOWED=NO \
    build

xcodebuild -quiet \
    -scheme UMusicApp \
    -destination 'generic/platform=macOS' \
    -derivedDataPath /tmp/umusic-v2-sprint1-app-macos \
    CODE_SIGNING_ALLOWED=NO \
    build

xcodebuild -quiet \
    -scheme UMusicPresentation \
    -destination 'generic/platform=iOS' \
    -derivedDataPath /tmp/umusic-v2-sprint1-ui-ios \
    CODE_SIGNING_ALLOWED=NO \
    build

xcodebuild -quiet \
    -scheme UMusicPresentation \
    -destination 'generic/platform=macOS' \
    -derivedDataPath /tmp/umusic-v2-sprint1-ui-macos \
    CODE_SIGNING_ALLOWED=NO \
    build
