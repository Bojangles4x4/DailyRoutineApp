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
- Read-only HealthKit authorization and daily summary service
- JavaScript-to-native message bridge
- iPhone-to-Watch current-context sync
- Watch-to-iPhone queued quick actions
- Web routine mapping for Complete next, Water +1, and mood check-ins
- Watch delivery feedback and refreshed completion totals
- Glanceable Watch dashboard with progress, next routine, and thumb-friendly actions
- WidgetKit complications for circular, inline, and rectangular layouts, including the Watch Smart Stack
- XcodeGen project specification

For safety, Complete next only marks unfinished checkbox routines. Medication logs and linked-app routines must still be completed deliberately on iPhone. If the Watch companion is not installed yet, the iPhone keeps the latest routine context ready and sends it when Watch Connectivity reports the companion is available.

The Watch app writes its latest received routine summary to an App Group shared with the WidgetKit extension. This lets complications show current progress without exposing the full routine database or Health information.

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
- Daily Routine data remains local-first until a separate sync design is explicitly approved.

## Apple references

- [Setting up HealthKit](https://developer.apple.com/documentation/healthkit/setting-up-healthkit)
- [Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Building a watchOS app](https://developer.apple.com/documentation/watchos-apps/building_a_watchos_app)
- [Transferring data with Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
