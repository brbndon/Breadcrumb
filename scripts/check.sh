#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcrun swift-format lint --strict --recursive Breadcrumb BreadcrumbTests
plutil -lint Breadcrumb/Breadcrumb.entitlements
