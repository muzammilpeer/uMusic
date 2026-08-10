#!/bin/sh
set -eu

workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir="$workspace_dir/Documentation/API"
export CLANG_MODULE_CACHE_PATH=/tmp/umusic-v2-api-clang-cache
export SWIFT_MODULE_CACHE_PATH=/tmp/umusic-v2-api-swift-cache
scratch_dir=/tmp/umusic-v2-api-build

mkdir -p "$output_dir"
set +e
swift package \
    --disable-sandbox \
    --package-path "$workspace_dir" \
    --scratch-path "$scratch_dir" \
    dump-symbol-graph \
    --skip-synthesized-members \
    --skip-inherited-docs \
    --minimum-access-level public
dump_status=$?
set -e

symbol_dir="$scratch_dir/arm64-apple-macosx/symbolgraph"
if [ "$dump_status" -ne 0 ]; then
    echo "SwiftPM returned $dump_status after symbol extraction; validating required production graphs" >&2
fi
for module in UMusicCore UMusicDomain UMusicImportClient; do
    test -s "$symbol_dir/$module.symbols.json"
    jq -r '.symbols[].identifier.precise' "$symbol_dir/$module.symbols.json" \
        | LC_ALL=C sort \
        > "$output_dir/$module.public-api.txt"
done
