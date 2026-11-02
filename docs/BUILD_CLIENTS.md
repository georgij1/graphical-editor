# Building Desktop and Mobile Clients

The graphical editor is a Flutter web application. Desktop and mobile clients
are separate Flutter build targets and must be compiled individually.

## Prerequisites

### Flutter SDK

Install Flutter (stable channel) and enable the desired platforms:

```bash
flutter doctor --android-licenses   # for Android
flutter config --enable-macos-desktop   # for macOS
flutter config --enable-linux-desktop   # for Linux
flutter config --enable-windows-desktop # for Windows
```

## Windows (x64)

```bash
flutter build windows --release
# Output: build/windows/runner/Release/
# Package: zip the contents of build/windows/runner/Release/
```

Result: `graphical_editor-windows.zip`

## macOS (Apple Silicon + Intel)

```bash
flutter build macos --release
# Output: build/macos/Build/Products/Release/
# Product: graphical_editor.app
# Package: zip the .app bundle
```

Result: `graphical_editor-macos.zip`

## Linux (x64)

```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/
# Package: tar czf graphical_editor-linux.tar.gz -C build/linux/x64/release/bundle/ .
```

Result: `graphical_editor-linux.tar.gz`

## Android (APK)

```bash
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/
# Product: app-release.apk
```

Result: `graphical_editor.apk`

## iOS (iPhone + iPad, signed)

Requires Xcode and an Apple Developer account:

```bash
flutter build ipa --release
# Output: build/ios/ipa/graphical_editor.ipa
```

Result: `graphical_editor-ios.ipa`

## Placing artifacts

Copy each built artifact into the `downloads/` directory:

```bash
cp graphical_editor-windows.zip downloads/
cp graphical_editor-macos.zip downloads/
cp graphical_editor-linux.tar.gz downloads/
cp graphical_editor.apk downloads/
cp graphical_editor-ios.ipa downloads/
```

Then rebuild and restart the frontend container:

```bash
docker compose build frontend
docker compose up -d frontend
```

The download dialog will automatically detect the files via HTTP HEAD probes
and show the "Скачать" button instead of "Скоро".
