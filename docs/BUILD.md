# Build and test

Run these commands from the repository root.
Use Xcode 26 or later.

## Build a local app

Run this command:

```sh
xcodebuild -project MindNative.xcodeproj -scheme MindNative \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```

The app is at `build/Build/Products/Debug/MindNative.app`.
This command does not make a Developer ID-signed app.

## Run tests

Run this command:

```sh
xcodebuild -project MindNative.xcodeproj -scheme MindNative \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO test
```

The command runs unit tests and UI tests.
Keep the test app in the foreground while the UI tests run.
Other windows can interrupt UI test actions.

## Build for Apple silicon and Intel

Run this command:

```sh
xcodebuild -project MindNative.xcodeproj -scheme MindNative \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO build
```

The app is at `build/Build/Products/Release/MindNative.app`.

## CI checks

GitHub Actions runs the workflow in `.github/workflows/ci.yml`.
It builds the app and test bundles.
It runs unit tests, UI tests, and static analysis.
It also builds a universal Release app.
CI does not publish a packaged app.

## App distribution

For a public app download, sign the app with a Developer ID Application certificate.
Send the signed app to Apple's notarization service.
Attach the notarization ticket before you make the final package.
Include `LICENSE` and `THIRD_PARTY_NOTICES.md` with the app.
Test the downloaded package on compatible Macs.

See [Apple's distribution instructions](https://developer.apple.com/developer-id/).
