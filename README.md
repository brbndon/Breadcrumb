# Breadcrumb

A local macOS app for understanding app and website usage over time.

## Features

- Dashboard and History views with app totals, optional website hosts, trends, and period comparisons.
- Search and filter records by app, website, and date.
- Pause or resume tracking from the menu bar; add app and website exclusions.
- Import and export history from Settings.

## Requirements

- macOS 26 or newer
- Xcode with Swift 6.2 or newer
- XcodeGen

## Build and check

```sh
xcodegen generate
./scripts/check.sh
./scripts/test.sh
```

Open `Breadcrumb.xcodeproj` to build and run the app in Xcode.

## Privacy and tracking

Tracking starts after first-run privacy setup. History stays on the Mac; the app does not upload it. Records include app name, bundle ID, and timestamps. Website hosts are recorded only when browser tracking is enabled. Browser support currently covers Arc, Dia, and Helium; macOS may ask for Automation permission. Full URLs, paths, query strings, credentials, and page titles are not saved.

Optional idle and media detection help separate active use from unattended or passive playback, but those signals are estimates. Screen-lock detection is not implemented. Recorded history and exported JSON can be sensitive, so keep exports private.