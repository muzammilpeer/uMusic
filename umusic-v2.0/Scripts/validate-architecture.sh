#!/bin/sh
set -eu

workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export CLANG_MODULE_CACHE_PATH=/tmp/umusic-v2-architecture-clang-cache
export SWIFT_MODULE_CACHE_PATH=/tmp/umusic-v2-architecture-swift-cache

swift test \
    --disable-sandbox \
    --package-path "$workspace_dir" \
    --scratch-path /tmp/umusic-v2-architecture-build \
    --filter ArchitectureTests

if rg -n 'import (AVFoundation|CoreData|CoreLocation|CoreML|CoreMotion|HealthKit|MediaPlayer|SwiftUI)' "$workspace_dir/Sources/UMusicImportClient"; then
    echo "UMusicImportClient contains a forbidden framework import" >&2
    exit 1
fi

if rg -n 'AVPlayer|NSManagedObject|NSManagedObjectContext|SecItem|MLMultiArray' "$workspace_dir/Sources/UMusicCore"; then
    echo "UMusicCore public source contains a forbidden implementation type" >&2
    exit 1
fi
