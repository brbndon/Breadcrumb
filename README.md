# Breadcrumb

A local macOS app-usage tracker built with SwiftUI and SwiftData. A three-pane window shows date ranges, a chronological journey, and app/site visit and transition reports. A menu bar item opens the window and Settings and pauses tracking.

Requires macOS 26+, Xcode with Swift 6.2+, and XcodeGen (`brew install xcodegen`). The generated Xcode project is ignored; `project.yml` is the build configuration.

```sh
xcodegen generate
./scripts/check.sh                 # formatter/linter and entitlement syntax
./scripts/test.sh                  # unsigned, isolated unit tests; artifacts in /tmp
```

Open `Breadcrumb.xcodeproj` to build/run normally. For an ad-hoc signed local build that includes the sandbox entitlements:

```sh
xcodebuild -project Breadcrumb.xcodeproj -scheme Breadcrumb -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/Breadcrumb-Signed \
  build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
```

For a repeatable manual menu smoke check, launch the signed executable with `BREADCRUMB_DEMO=1`. Complete the privacy screen, open Settings, and verify that Stop/Resume Tracking in the status menu updates the Settings switch in both directions. Close the main window, use Open Breadcrumb, and confirm exactly one main window reopens; then open Settings from the status menu. Quit the demo afterward. The demo does not collect real foreground events or persist history.

The unit-test scheme sets `BREADCRUMB_TESTING=1`: the app host uses in-memory storage, nonpersistent tracking preferences, and no live capture. `BREADCRUMB_DEMO=1` provides the same isolation for UI smoke checks. These flags do not enable browser capture. Normal launches use the persistent app store. No test should use or delete personal history.

Settings → **Dock & App Switcher** offers **Hide from Dock when no windows are open** (off by default). When enabled, closing both Breadcrumb and Settings removes the app from the Dock and Command-Tab; its menu bar item and tracking remain available. Opening either window restores normal Dock presence. Minimized windows still count as open. This preference is saved locally; demo and test runs keep it in memory.

## Privacy and tracking

Tracking starts only after first-run privacy setup. Breadcrumb keeps app name, bundle ID, timestamps, and optional website host locally. Nothing is uploaded. It never logs app names, hosts, URLs, or titles. Pause/resume is shared by Settings and the menu. Exclusions apply to new capture, including browser hosts; existing records are kept.

Arc and Dia host tracking are independently opt-in in Settings. Only an enabled foreground browser is queried, at five-second intervals, using Apple Events. macOS may request Automation permission. Without permission, app-only tracking continues and Settings explains how to recover. URLs are parsed in memory and discarded; paths, queries, credentials, and titles are never saved. Browser Automation targets are restricted to Arc and Dia. File access is user-selected for app exclusion, import, and export. No network entitlement is requested.

Pausing, exclusions, sleep/display sleep, shutdown, and capture errors close the current tracking segment. Reports do not bridge those gaps. On reopening after an unclean exit, the last unclosed visit is conservatively ended at its start because its actual end is unknown. Active is an estimate: each visit contributes at most five minutes, and an open newest visit contributes zero. No keyboard/mouse idle detector or separate session-lock detector is implemented.

## Storage and earlier history

New history uses `Breadcrumb/Breadcrumb.store` inside the app's Application Support directory (inside its container when sandboxed). Settings has **Show History Folder**, JSON export/import, and confirmed deletion. Storage errors are surfaced; launch errors offer Retry rather than replacing the store. Failed edits are rolled back.

The earlier unsigned build used `~/Library/Application Support/default.store`; an older sandboxed build may have `default.store` inside its container. These files are **not moved, opened, or deleted automatically**. To retain them, close the older build and use **Import Previous History…** in first-run setup or Settings. Select the folder containing `default.store` and its `-wal`, if present. Breadcrumb copies these into a temporary staging directory before opening them, preserving the originals including their shared-memory sidecar. Keep the old build closed during the copy. Existing UUIDs are skipped on reimport.

The model adds an optional visit-end timestamp and a timestamp index using SwiftData's automatic migration. Migration of an old store happens only on the staging copy during explicit import. No existing store is deleted as an error-recovery action. Delete All affects the active store only; earlier stores and exported files are kept. JSON archives are versioned, use milliseconds since the Unix epoch, and include sensitive history. Imports and exports support up to 250,000 events; imports are limited to 128 MiB. Keep exported files private.

Reports fetch the selected interval in timestamp order and aggregate in batches, recomputing on range/data changes rather than every clock tick. The journey fetch is limited to 200 newest events. Formatting uses `.swift-format` and Apple's bundled formatter.
