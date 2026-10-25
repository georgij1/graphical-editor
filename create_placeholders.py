# -*- coding: utf-8 -*-
"""Create placeholder download files for the client download dialog."""
import io
import os
import zipfile
import tarfile
import gzip

DOWNLOADS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'downloads')
os.makedirs(DOWNLOADS_DIR, exist_ok=True)

# 1. Empty ZIP files (Windows, macOS)
for name in ['graphical_editor-windows.zip', 'graphical_editor-macos.zip']:
    path = os.path.join(DOWNLOADS_DIR, name)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('README.txt', 'Placeholder for graphical editor client.\nReplace with a real build artifact.\n')
    print(f'Created {path} ({os.path.getsize(path)} bytes)')

# 2. Empty tar.gz (Linux)
path = os.path.join(DOWNLOADS_DIR, 'graphical_editor-linux.tar.gz')
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode='w') as tar:
    info = tarfile.TarInfo(name='README.txt')
    info.size = len(b'Placeholder for graphical editor client.\nReplace with a real build artifact.\n')
    tar.addfile(info, io.BytesIO(b'Placeholder for graphical editor client.\nReplace with a real build artifact.\n'))
with gzip.open(path, 'wb') as f:
    f.write(buf.getvalue())
print(f'Created {path} ({os.path.getsize(path)} bytes)')

# 3. Empty ZIP as APK (Android)
path = os.path.join(DOWNLOADS_DIR, 'graphical_editor.apk')
with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('AndroidManifest.xml', '<manifest package="com.example.graphical_editor" />\n')
    z.writestr('classes.dex', b'')  # empty DEX
    z.writestr('resources.arsc', b'')  # empty resources
print(f'Created {path} ({os.path.getsize(path)} bytes)')

# 4. Empty ZIP as IPA (iOS)
path = os.path.join(DOWNLOADS_DIR, 'graphical_editor-ios.ipa')
with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('Payload/graphical_editor.app/Info.plist', '<plist version="1.0"><dict><key>CFBundleDisplayName</key><string>graphical_editor</string></dict></plist>\n')
    z.writestr('Payload/graphical_editor.app/graphical_editor', b'')  # empty binary
print(f'Created {path} ({os.path.getsize(path)} bytes)')

print('\nAll placeholder files created in', DOWNLOADS_DIR)
