#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
module_cache="$project_dir/build/StrictModuleCache"
target="$(uname -m)-apple-macosx13.0"
source_files=("$project_dir"/Sources/*.swift)
# Every source except the app entry point: its @main collides with the test runner's.
test_sources=(${source_files:#*/CodexUsageMicro.swift})
test_files=("$project_dir"/Tests/*.swift)
test_binary="$project_dir/build/CodexUsageMicroTests"

for script in "$project_dir/build.sh" "$project_dir/install.sh" "$project_dir/package-release.sh"; do
  zsh -n "$script"
done

mkdir -p "$module_cache"

xcrun swift-format lint \
  --strict \
  --recursive \
  --configuration "$project_dir/.swift-format" \
  "$project_dir/Sources" \
  "$project_dir/Tests"

swiftc \
  -typecheck \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -target "$target" \
  -module-cache-path "$module_cache" \
  -framework AppKit \
  -framework Foundation \
  "${source_files[@]}"

swiftc \
  -parse-as-library \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -target "$target" \
  -module-cache-path "$module_cache" \
  -framework AppKit \
  -framework Foundation \
  "${test_sources[@]}" \
  "${test_files[@]}" \
  -o "$test_binary"

"$test_binary"
