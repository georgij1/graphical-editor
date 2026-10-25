import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../downloads/download_target.dart';
import '../../l10n/app_localizations.dart';

/// Checks whether a client artifact is available for download.
typedef DownloadAvailability = Future<bool> Function(Uri uri);

/// Dialog listing the platforms the editor can be installed on, with a
/// download action for every artifact that is actually published on the
/// server (see the `downloads/` directory / nginx).
class DownloadsDialog extends StatefulWidget {
  const DownloadsDialog({super.key, this.probe});

  /// Optional availability probe (injected in tests).
  final DownloadAvailability? probe;

  static Future<void> show(BuildContext context, {DownloadAvailability? probe}) {
    return showDialog<void>(
      context: context,
      builder: (_) => DownloadsDialog(probe: probe),
    );
  }

  @override
  State<DownloadsDialog> createState() => _DownloadsDialogState();
}

class _DownloadsDialogState extends State<DownloadsDialog> {
  final Map<String, bool> _available = <String, bool>{};
  final Set<String> _opening = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _probeAll();
  }

  Future<bool> _httpProbe(Uri uri) async {
    final client = http.Client();
    try {
      final response =
          await client.head(uri).timeout(const Duration(seconds: 6));
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> _probeAll() async {
    final probe = widget.probe ?? _httpProbe;
    final base = downloadsBaseUrl();
    final entries = await Future.wait(downloadTargets.map((target) async {
      final ok = await probe(downloadUri(base, target.fileName));
      return MapEntry(target.id, ok);
    }));
    if (!mounted) return;
    setState(() {
      _available
        ..clear()
        ..addEntries(entries);
      _loading = false;
    });
  }

  Future<void> _download(DownloadTarget target) async {
    setState(() => _opening.add(target.id));
    final uri = downloadUri(downloadsBaseUrl(), target.fileName);
    final ok = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!mounted) return;
    setState(() => _opening.remove(target.id));
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotOpenLink(target.title))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <String, List<DownloadTarget>>{};
    for (final target in downloadTargets) {
      groups.putIfAbsent(target.group, () => <DownloadTarget>[]).add(target);
    }

    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.download_outlined),
          const SizedBox(width: 10),
          Text(context.tr('Download client')),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: 460,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final entry in groups.entries) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                        child: Text(
                          context.tr(entry.key).toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 0.8,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      for (final target in entry.value)
                        _TargetTile(
                          target: target,
                          available: _available[target.id] ?? false,
                          opening: _opening.contains(target.id),
                          onDownload: () => _download(target),
                        ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      context.tr('Ready-made builds are served from the downloads/ folder. Unavailable platforms are marked “Soon”.'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Close')),
        ),
      ],
    );
  }
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.target,
    required this.available,
    required this.opening,
    required this.onDownload,
  });

  final DownloadTarget target;
  final bool available;
  final bool opening;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(target.icon),
        title: Text(target.title),
        subtitle: Text(context.tr(target.subtitle)),
        trailing: opening
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : available
                ? FilledButton.tonalIcon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(context.tr('Download')),
                  )
                : Chip(
                    label: Text(context.tr('Soon')),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
      ),
    );
  }
}
