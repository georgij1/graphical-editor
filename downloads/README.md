# Client downloads

This directory contains downloadable client binaries for the graphical editor.
It is mounted into the nginx container at `/usr/share/nginx/html/downloads` and
served at `http://<host>/downloads/`.

## Expected files

| File | Platform | Description |
|------|----------|-------------|
| `graphical_editor-windows.zip` | Windows (x64) | Portable client for Windows 10/11 |
| `graphical_editor-macos.zip` | macOS | Build for Apple Silicon and Intel |
| `graphical_editor-linux.tar.gz` | Linux (x64) | Build for Linux |
| `graphical_editor.apk` | Android | APK for phones and tablets |
| `graphical_editor-ios.ipa` | iOS | Build for iPhone and iPad (signed) |

## How to build clients

See [`BUILD_CLIENTS.md`](BUILD_CLIENTS.md) for step-by-step build instructions
for each platform.

## Placeholder files

The files currently in this directory are placeholders (empty archives) so that
the download UI shows "Скачать" instead of "Скоро". Replace them with real
build artifacts before deploying to production.
