#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "usage: $0 <rust-tag> <xcframework-zip> <generated-swift-directory>" >&2
    exit 64
}

[[ $# -eq 3 ]] || usage

rust_tag=$1
archive=$2
bindings_directory=$3

[[ $rust_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "error: Rust tag must have the form vMAJOR.MINOR.PATCH" >&2
    exit 65
}
[[ -f $archive ]] || {
    echo "error: XCFramework archive not found: $archive" >&2
    exit 66
}
[[ -d $bindings_directory ]] || {
    echo "error: generated Swift directory not found: $bindings_directory" >&2
    exit 66
}

shopt -s nullglob
binding_files=("$bindings_directory"/*.swift)
(( ${#binding_files[@]} > 0 )) || {
    echo "error: no generated Swift bindings found in $bindings_directory" >&2
    exit 66
}

repository_root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$repository_root/Package.swift"
source_directory="$repository_root/Sources/SwiftLayout"
download_url="https://github.com/hakkabon/Layout/releases/download/$rust_tag/Layout.xcframework.zip"
checksum=$(swift package compute-checksum "$archive")

# This is the single owner of how a native Layout release is represented by
# the Swift package. The Rust repository supplies artifacts, not package paths.
for binding in "${binding_files[@]}"; do
    cp "$binding" "$source_directory/$(basename "$binding")"
done

url_count=$(grep -c 'url: "https://github.com/hakkabon/Layout/releases/download/' "$manifest" || true)
checksum_count=$(grep -c 'checksum: "' "$manifest" || true)
[[ $url_count -eq 1 && $checksum_count -eq 1 ]] || {
    echo "error: expected exactly one Layout binary URL and checksum in Package.swift" >&2
    exit 65
}

sed -E -i '' "s#url: \"https://github.com/hakkabon/Layout/releases/download/[^\"]+\"#url: \"$download_url\"#" "$manifest"
sed -E -i '' "s#checksum: \"[^\"]+\"#checksum: \"$checksum\"#" "$manifest"

manifest_dump=$(mktemp)
trap 'rm -f "$manifest_dump"' EXIT
if ! (cd "$repository_root" && swift package dump-package >"$manifest_dump") || [[ ! -s $manifest_dump ]]; then
    echo "error: updated Package.swift is not a valid Swift package manifest" >&2
    exit 65
fi

echo "Updated Swift-Layout for native release ${rust_tag#v}"
