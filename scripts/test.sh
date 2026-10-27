#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodegen generate
artifact_path="${BREADCRUMB_DERIVED_DATA:-/tmp/Breadcrumb-DerivedData}"
xcodebuild -project Breadcrumb.xcodeproj -scheme Breadcrumb -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$artifact_path" \
  -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO
