#!/usr/bin/env bash
# Builds the desktop/mobile clients that the current OS can produce into
# downloads/. macOS build must run on macOS; Linux build must run on Linux;
# iOS needs Xcode plus a signing identity/team set in Xcode.
# The web client is optional and not packaged here.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
mkdir -p downloads

case "$(uname -s)" in
    Darwin)
        echo "==> macOS"
        [ -d macos ] || flutter create --platforms=macos .
        flutter build macos --release
        ( cd build/macos/Build/Products/Release && zip -qr "$root/downloads/graphical_editor-macos.zip" . )

        echo "==> iOS (requires Xcode signing)"
        if [ -d ios ]; then
            flutter build ipa --release && \
                cp build/ios/ipa/*.ipa "$root/downloads/graphical_editor-ios.ipa" || \
                echo "   iOS build skipped (no signing configured)."
        else
            echo "   ios/ not present - run: flutter create --platforms=ios ."
        fi
        ;;
    Linux)
        echo "==> Linux"
        [ -d linux ] || flutter create --platforms=linux .
        flutter build linux --release
        tar -czf "$root/downloads/graphical_editor-linux.tar.gz" \
            -C build/linux/x64/release/bundle .
        ;;
    *)
        echo "Unsupported host: $(uname -s)"
        ;;
esac

echo "Artifacts:"; ls -la downloads
