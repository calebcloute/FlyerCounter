# FlyerCounter

FlyerCounter is a native **iOS/iPadOS** app built with **SwiftUI** (Xcode project, no Swift Package Manager / CocoaPods / Carthage). It tracks GPS walking routes for door-to-door flyer distribution, auto-detects flyer drops, manages map area boundaries, and provides voice/haptic feedback. All data is stored locally (`UserDefaults` + `FileManager` + JSON); there is **no backend, database, or network service**.

- Entry point: `FlyerCounter/FlyerCounterApp.swift` (`@main`)
- Xcode project: `FlyerCounter.xcodeproj`, scheme `FlyerCounter`
- Language: Swift 5.0, min deployment target **iOS 17.0**, `SDKROOT = iphoneos`
- Frameworks used: SwiftUI, CoreLocation, MapKit, UIKit, Combine, UserNotifications, AVFoundation, AudioToolbox, CryptoKit, CoreGraphics — all Apple-only.
- No third-party dependencies, no lockfiles, no package manager. There is nothing to `install`.

## Standard build / run (requires macOS + Xcode 15+)

Open in Xcode and press Run, or from the command line:

```bash
# Build
xcodebuild -project FlyerCounter.xcodeproj -scheme FlyerCounter \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

# Run tests (none are currently defined in the project)
xcodebuild -project FlyerCounter.xcodeproj -scheme FlyerCounter \
  -destination 'platform=iOS Simulator,name=iPhone 15' test
```

To exercise route tracking in the Simulator, feed a simulated GPS route via **Features → Location**. Background location, real GPS accuracy, and haptics are only fully testable on a physical iOS 17+ device (automatic code signing with `DEVELOPMENT_TEAM` is configured for on-device runs; the Simulator needs no signing).

## Cursor Cloud specific instructions

**This project cannot be built, run, or tested in the Cursor Cloud environment.** Cloud Agent VMs run **Linux (Ubuntu x86_64)**, but this is a native iOS app that requires the **macOS + Xcode toolchain** (`xcodebuild`, iOS SDK, iOS Simulator). Apple does not distribute Xcode or the iOS SDK for Linux, and Swift-for-Linux does not provide the Apple frameworks (SwiftUI, UIKit, CoreLocation, MapKit, etc.) that essentially every source file imports. Consequences for future cloud agents:

- Do **not** attempt to install a Swift toolchain to "build" the app on Linux — it will fail because the iOS SDK/Apple frameworks are unavailable. There is no lint/test/build/run command that works here.
- There are **no dependencies to install** (no package manager). The startup update script is intentionally a no-op.
- Code changes can be authored/reviewed on Linux, but must be compiled and manually tested on macOS + Xcode (Simulator or device). GPS-dependent behavior needs a simulated or real location.
