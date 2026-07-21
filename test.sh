#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
module_cache="$project_dir/build/StrictModuleCache"
source_files=("$project_dir"/Sources/*.swift)
test_files=("$project_dir"/Tests/*.swift)
test_binary="$project_dir/build/CodexUsageMicroTests"

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
  -target arm64-apple-macosx13.0 \
  -module-cache-path "$module_cache" \
  -framework AppKit \
  -framework Foundation \
  "${source_files[@]}"

swiftc \
  -parse-as-library \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -module-cache-path "$module_cache" \
  -framework AppKit \
  -framework Foundation \
  "$project_dir/Sources/AppConfiguration.swift" \
  "$project_dir/Sources/RefreshConfiguration.swift" \
  "$project_dir/Sources/UsageModels.swift" \
  "$project_dir/Sources/CodexResponseParser.swift" \
  "$project_dir/Sources/DiagnosticText.swift" \
  "$project_dir/Sources/JSONLineBuffer.swift" \
  "$project_dir/Sources/CodexClient.swift" \
  "${test_files[@]}" \
  -o "$test_binary"

"$test_binary"
