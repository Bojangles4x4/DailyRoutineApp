# Daily Routine for Apple platforms

This folder is the native foundation for turning Daily Routine into an iPhone app with HealthKit support and an Apple Watch companion.

## Architecture

- The iPhone target is a SwiftUI app that hosts the existing offline web interface in `WKWebView`.
- A narrow JavaScript bridge exposes native HealthKit summaries and Apple Watch events to the web app.
- The Watch target is a focused SwiftUI companion for quick routine actions.
- Health access starts read-only and limited to steps, sleep, and workouts.
- Watch actions use Watch Connectivity and queue safely when the phone is unavailable.

This is intentionally more than a website wrapper. The native HealthKit and Watch experiences provide the platform-specific utility Apple expects from an App Store app.

## Current foundation

- Native iPhone and watchOS source structure
- Read-only HealthKit authorization, daily summary service, reviewable sleep-time suggestions, and an optional automatic steps-goal routine item
- JavaScript-to-native message bridge
- iPhone-to-Watch current-context sync
- Watch-to-iPhone queued quick actions
- Exact checkbox and medication selection from the Watch routine list
- Configurable bottom Watch shortcut, with Water +1 as the default
- Dictated Watch capture for general notes, prayers, and action items
- Watch delivery feedback and refreshed completion totals
- Glanceable Watch dashboard with a roomier progress header, larger routine tap targets, and compact fixed bottom actions
- WidgetKit complications for circular, inline, and rectangular layouts, including the Watch Smart Stack
- Morning Foundation synchronization that keeps Watch quick actions and complications locked until Truth Before Tasks and any configured convictions are complete on iPhone
- App Store icon catalogs, privacy manifests for App Group user defaults, and bundled privacy/support pages
- XcodeGen project specification

Tapping a checkbox or medication row updates that exact routine; tapping a completed row reopens it. Medication taps record the current time, with an AM/PM confirmation on Watch when the time does not match the routine section. Linked-app routines remain on iPhone. All Watch actions remain locked until the Morning Foundation is completed on the iPhone for the local calendar day. If personal convictions are configured, they are part of that foundation. If the Watch companion is not installed yet, the iPhone keeps the latest routine context ready and sends it when Watch Connectivity reports the companion is available.

The Watch app writes its latest received routine summary to an App Group shared with the WidgetKit extension. This lets complications show current progress without exposing the full routine database or Health information.

See [APP_STORE_SUBMISSION.md](APP_STORE_SUBMISSION.md) for the prepared listing copy, App Privacy answers, HealthKit disclosure, TestFlight instructions, review notes, and final submission checklist.

## Prerequisites

1. Install the full version of Xcode from the Mac App Store. Command Line Tools alone cannot build or sign iPhone and Watch apps.
2. Choose your Apple Developer team and final bundle identifier.
3. Install XcodeGen with Homebrew: `brew install xcodegen`.
4. From this folder, run `xcodegen generate` and open `DailyRoutineApple.xcodeproj`.
5. In Xcode, select your developer team for both targets and let Xcode manage signing.
6. Test HealthKit and Watch Connectivity on a physical iPhone and Apple Watch.

Project generation applies an Xcode 26 compatibility adjustment so the modern watchOS app is embedded in the iPhone app's `PlugIns` folder.

## Privacy defaults

- Health access is optional and requested only after a person chooses to connect it.
- The first version reads only steps, sleep, and workouts.
- It does not write medication, mood, prayer, or routine data to HealthKit.
- Health information stays on the person’s devices and is not used for advertising or analytics.
- Automatic Health-based step values are excluded from Private sync. Sleep suggestions become routine history only after the person applies them.
- Daily Routine data remains local-first until a separate sync design is explicitly approved.

## Apple references

- [Setting up HealthKit](https://developer.apple.com/documentation/healthkit/setting-up-healthkit)
- [Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Building a watchOS app](https://developer.apple.com/documentation/watchos-apps/building_a_watchos_app)
- [Transferring data with Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
