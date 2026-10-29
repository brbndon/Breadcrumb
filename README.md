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

For a repeatable manual smoke check, build with a distinct bundle identifier (`PRODUCT_BUNDLE_IDENTIFIER=com.branalytic.Breadcrumb.Demo`) and launch that signed executable with `BREADCRUMB_DEMO=1`. This avoids UI automation confusing it with an installed copy. The demo seeds synthetic visits across three days, including more than 200 visits, ten apps/sites, duplicate names, timestamp ties, segment gaps, a long visit, and an ongoing visit. Complete the privacy screen, open Settings, and verify that Stop/Resume Tracking in the status menu updates the Settings switch in both directions. Close the main window, use Open Breadcrumb, and confirm exactly one main window reopens; then open Settings from the status menu. Quit the demo afterward. The demo does not collect real foreground events, persist history/preferences, or change actual login registration.

The unit-test scheme sets `BREADCRUMB_TESTING=1`: the app host uses in-memory storage, nonpersistent tracking preferences, and no live capture. `BREADCRUMB_DEMO=1` provides the same isolation for UI smoke checks. These flags do not enable browser capture. Normal launches use the persistent app store. No test should use or delete personal history.

Settings → **Dock & App Switcher** offers **Hide from Dock when no windows are open** (off by default). When enabled, closing both Breadcrumb and Settings removes the app from the Dock and Command-Tab; its menu bar item and tracking remain available. Opening either window restores normal Dock presence. Minimized windows still count as open. This preference is saved locally; demo and test runs keep it in memory.

## Privacy and tracking

Tracking starts only after first-run privacy setup. Breadcrumb keeps app name, bundle ID, timestamps, and optional website host locally. Nothing is uploaded. It never logs app names, hosts, URLs, or titles. Pause/resume is shared by Settings and the menu. Exclusions apply to new capture, including browser hosts; existing records are kept.

Arc and Dia host tracking are independently opt-in in Settings. Only an enabled foreground browser is queried, at five-second intervals, using Apple Events. macOS may request Automation permission. Without permission, app-only tracking continues and Settings explains how to recover. URLs are parsed in memory and discarded; paths, queries, credentials, and titles are never saved. Browser Automation targets are restricted to Arc and Dia. File access is user-selected for app exclusion, import, and export. No network entitlement is requested.

Pausing, exclusions, sleep/display sleep, shutdown, and capture errors close the current tracking segment. Reports do not bridge those gaps. On reopening after an unclean exit, the last unclosed visit is conservatively ended at its start because its actual end is unknown. Estimated time gives each original visit at most five minutes, then clips that contribution to the selected period. An ongoing newest visit contributes zero until its end can be resolved. Recorded visit duration is uncapped and can include unattended time. Optional **Pause when idle** is off by default. After five minutes without input, it closes the current visit at the inferred last-input time, clamped to its original start, and resumes with a new segment at the next observed active sample. Passive reading can look idle. Only aggregate idle duration and console-session state are read, after consent, on a five-second runtime timer even with windows closed. No key values, mouse positions, event taps, or input contents are collected. Console inactivity stops capture independently of manual pause and sleep; unavailable required activity state pauses capture with a retry action. Actual screen-lock detection is deferred: documented console-session and display-sleep signals are not proof of lock state. Historical records are not rewritten.

## Storage and earlier history

New history uses `Breadcrumb/Breadcrumb.store` inside the app's Application Support directory (inside its container when sandboxed). Settings has **Show History Folder**, JSON export/import, and confirmed deletion. Storage errors are surfaced; launch errors offer Retry rather than replacing the store. Failed edits are rolled back.

The earlier unsigned build used `~/Library/Application Support/default.store`; an older sandboxed build may have `default.store` inside its container. These files are **not moved, opened, or deleted automatically**. To retain them, close the older build and use **Import Previous History…** in first-run setup or Settings. Select the folder containing `default.store` and its `-wal`, if present. Breadcrumb copies these into a temporary staging directory before opening them, preserving the originals including their shared-memory sidecar. Keep the old build closed during the copy. Existing UUIDs are skipped on reimport.

The model adds an optional visit-end timestamp and a timestamp index using SwiftData's automatic migration. Migration of an old store happens only on the staging copy during explicit import. No existing store is deleted as an error-recovery action. Delete All affects the active store only; earlier stores and exported files are kept. JSON archives are versioned, use milliseconds since the Unix epoch, and include sensitive history. Imports and exports support up to 250,000 events; imports are limited to 128 MiB. Keep exported files private.

## Exploring history

Search names, bundle IDs, or opted-in hosts across the complete selected period. Text, All/Apps/Sites, and an exact report-entry selection are combined before pagination. The journey loads 100 visits at a time with **Load older**, and offers distinct loading, exhausted, no-match, and retry states. Rows retain original timestamps and resolve recorded duration from the original next visit, including across page/filter boundaries. Carry-in visits are marked as starting before the period.

Reports always cover the whole selected period. Expand beyond six apps/sites, sort by Visits or Estimated time, and select a row to filter the journey to that exact app or host. Apps with the same display name remain distinct by bundle ID. A visit overlapping a period counts once there, even if its five-minute contribution expired earlier. A carry-in can therefore count in adjacent periods; switches count only at destinations inside the period and never bridge closed segments. Site visits do not add another browser-app count.

Today, Yesterday, Monday-based Week, and All remain available. **Custom** uses inclusive local-calendar dates; apply edits explicitly. Future or reversed dates are rejected, preserving the last valid period. **Compare preceding period** shows explicit dates/cutoffs and signed absolute changes in switches, distinct recorded apps, and estimated minutes. Today and Week compare through the corresponding local clock time; custom ranges compare against an equal preceding block of calendar days. DST gaps use the next valid wall time, and repeated times use the first occurrence. Missing history shows **No recorded history** and unavailable changes. All has no preceding-period comparison. **Refresh history**, date changes, store revisions, and day rollover capture a new as-of time; typing and ordinary clock ticks do not rebuild reports.

Queries and aggregation stay on the main actor and stream original records in batches; views retain only loaded value snapshots. Timestamp ties use descending UUID-string order without a model/index migration. Formatting uses `.swift-format` and Apple's bundled formatter.

## Launch at login

Settings reads the actual ServiceManagement main-app state. Launch at login starts off unless already registered externally, and registration changes only after an explicit toggle. Approval requirements and operation failures are shown; **Open Login Items Settings** offers recovery. Status refreshes when Settings appears and when the app becomes active. A documented login launch can stay in the menu bar after consent; an ordinary manual launch opens Breadcrumb, and first-run privacy setup remains visible. Login does not grant consent or clear a manual pause. Demos/tests inject a fake service; a real registration/login cycle must be checked manually in a signed installed build.

For extended isolated verification, `BREADCRUMB_LARGE_TEST=1 TEST_RUNNER_BREADCRUMB_LARGE_TEST=1 ./scripts/test.sh` additionally exercises a session-owned 250,000-event store. Normal tests use smaller fixtures. No verification step should open personal history, force screen lock, log out, or automatically register a login item.

For a signed public-activity smoke check, add `BREADCRUMB_ACTIVITY_PROBE=1` alongside `BREADCRUMB_DEMO=1`. Only in this combination does the demo enable live coarse monitoring, after consent, with a synthetic foreground identity, in-memory store/preferences, and fake login service. It never queries a real foreground app or browser. Actual screen-lock detection and a physical login cycle are not claimed by this probe.
