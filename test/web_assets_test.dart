import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('web assets', () {
    test('the loading screen is present and self-removing', () {
      final html = File('web/index.html').readAsStringSync();

      expect(html, contains('id="flutter-loading"'));
      expect(html, contains('icons/Icon-192.png'));
      // It must disappear once Flutter paints, and never block the app.
      expect(html, contains('flutter-first-frame'));
      expect(html, contains("querySelector('flutter-view, flt-glass-pane')"));
      expect(html, contains('is-hidden'));
      expect(html, contains('flutter_bootstrap.js'));
    });

    test('the loading screen follows the saved theme', () {
      final html = File('web/index.html').readAsStringSync();

      // The stored preference is read before the first paint.
      expect(html, contains("var STORAGE_THEME = 'app_theme'"));
      expect(html, contains('(prefers-color-scheme: dark)'));
      expect(html, contains('data-theme'));
      expect(html, contains('html[data-theme="dark"]'));
      expect(html, contains('var(--splash-bg)'));
      // Browser chrome follows the theme as well.
      expect(html, contains('theme-color-meta'));
      // The saved language drives the caption.
      expect(html, contains("var STORAGE_LANG = 'app_lang'"));
    });

    test('the manifest describes the app', () {
      final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
          as Map<String, dynamic>;

      expect(manifest['name'], contains('FXML Editor'));
      expect(manifest['background_color'], '#039ED3');
      expect(manifest['theme_color'], '#039ED3');

      final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
      expect(icons, isNotEmpty);
      for (final icon in icons) {
        expect(File('web/${icon['src']}').existsSync(), isTrue,
            reason: '${icon['src']} is missing');
      }
    });

    test('every icon referenced by the manifest exists', () {
      for (final path in const <String>[
        'web/favicon.png',
        'web/icons/Icon-192.png',
        'web/icons/Icon-512.png',
        'web/icons/Icon-maskable-192.png',
        'web/icons/Icon-maskable-512.png',
      ]) {
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');
      }
    });
  });
}