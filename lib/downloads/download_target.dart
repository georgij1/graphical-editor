import 'package:flutter/material.dart';

/// One downloadable platform client shown in the downloads dialog.
class DownloadTarget {
  const DownloadTarget({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.group,
    required this.fileName,
    required this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final String group;
  final String fileName;
  final IconData icon;
}

/// Clients the editor can be built for. Each entry maps to a file served from
/// the downloads directory (see `DOWNLOADS_BASE_URL`), e.g.
/// `/downloads/graphical_editor-windows.zip`.
const List<DownloadTarget> downloadTargets = <DownloadTarget>[
  DownloadTarget(
    id: 'windows',
    title: 'Windows',
    subtitle: 'Portable client for Windows 10/11 (x64)',
    group: 'Desktop',
    fileName: 'graphical_editor-windows.zip',
    icon: Icons.desktop_windows_outlined,
  ),
  DownloadTarget(
    id: 'macos',
    title: 'macOS',
    subtitle: 'Build for Apple Silicon and Intel',
    group: 'Desktop',
    fileName: 'graphical_editor-macos.zip',
    icon: Icons.laptop_mac_outlined,
  ),
  DownloadTarget(
    id: 'linux',
    title: 'Linux',
    subtitle: 'Build for Linux (x64, tar.gz)',
    group: 'Desktop',
    fileName: 'graphical_editor-linux.tar.gz',
    icon: Icons.computer_outlined,
  ),
  DownloadTarget(
    id: 'android',
    title: 'Android',
    subtitle: 'APK for phones and tablets',
    group: 'Mobile',
    fileName: 'graphical_editor.apk',
    icon: Icons.android_outlined,
  ),
  DownloadTarget(
    id: 'ios',
    title: 'iOS',
    subtitle: 'Build for iPhone and iPad (signed)',
    group: 'Mobile',
    fileName: 'graphical_editor-ios.ipa',
    icon: Icons.phone_iphone_outlined,
  ),
];

/// Base URL where client artifacts are served. Override at build time with
/// `--dart-define=DOWNLOADS_BASE_URL=...`; defaults to the same-origin
/// `/downloads` directory (served by nginx in the Docker setup).
String downloadsBaseUrl() {
  const fromEnv = String.fromEnvironment('DOWNLOADS_BASE_URL');
  return fromEnv.isNotEmpty ? fromEnv : '/downloads';
}

/// Absolute URI of a client artifact. Relative bases are resolved against the
/// page's own origin so the link works regardless of how the app is hosted.
Uri downloadUri(String baseUrl, String fileName) {
  final normalized = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final full = Uri.parse('$normalized/$fileName');
  return full.hasScheme ? full : Uri.base.resolve(full.toString());
}
