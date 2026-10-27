# Breadcrumb

A local-only macOS app that tracks which app is in front and shows your path through the day: a journey timeline, summary stats, top apps, and most-used transitions.

- SwiftUI, SwiftData, macOS 26+. Capture uses `NSWorkspace` activation notifications (no polling).
- Data never leaves the Mac. Pause and delete-all live in Settings (⌘,).

## Build

```sh
brew install xcodegen   # once
xcodegen generate
xcodebuild -scheme Breadcrumb -destination 'platform=macOS' test
```

`project.yml` is the source of truth; `Breadcrumb.xcodeproj` is generated and git-ignored.

## Roadmap

Idle/lock/sleep handling, app exclusions, export, opt-in browser-site tracking (Apple Events, host only by default), first-run privacy explainer.
