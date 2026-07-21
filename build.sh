#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
app_name="Codex Usage Micro"
app_dir="$project_dir/build/$app_name.app"
staging_root=$(mktemp -d "${TMPDIR:-/private/tmp}/codex-usage-micro-build.XXXXXX")
staging_app="$staging_root/$app_name.app"
contents_dir="$staging_app/Contents"
binary_dir="$contents_dir/MacOS"

trap 'rm -rf "$staging_root"' EXIT

mkdir -p "$binary_dir" "$project_dir/build/ModuleCache"

swiftc \
  -O \
  -parse-as-library \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "$project_dir/build/ModuleCache" \
  -framework AppKit \
  -framework Foundation \
  "$project_dir/Sources/CodexUsageMicro.swift" \
  "$project_dir/Sources/RefreshConfiguration.swift" \
  -o "$binary_dir/CodexUsageMicro"

cp "$project_dir/Info.plist" "$contents_dir/Info.plist"

if [[ -e "$app_dir" ]]; then
  rm -rf "$app_dir"
fi
ditto --noextattr --noqtn "$staging_app" "$app_dir"
xattr -cr "$app_dir"
codesign --force --sign - "$app_dir"
xattr -d com.apple.FinderInfo "$app_dir" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$app_dir" 2>/dev/null || true
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
