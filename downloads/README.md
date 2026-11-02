# Client downloads

This directory contains downloadable client binaries for the graphical editor.
It is mounted into the nginx container at `/usr/share/nginx/html/downloads` and
served at `http://<host>/downloads/`.

## Available clients

| File | Platform | Description |
|------|----------|-------------|
| `graphical_editor-windows.zip` | Windows (x64) | Portable client for Windows 10/11 |
| `graphical_editor-linux.tar.gz` | Linux (x64) | Build for Linux |

## How to build clients

See [`BUILD_CLIENTS.md`](BUILD_CLIENTS.md) for step-by-step build instructions
for each platform.
