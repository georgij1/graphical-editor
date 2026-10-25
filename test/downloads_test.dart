import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:graphical_editor/downloads/download_target.dart';
import 'package:graphical_editor/l10n/app_localizations.dart';
import 'package:graphical_editor/ui/widgets/downloads_dialog.dart';

Future<bool> _probe(Uri uri) async =>
    uri.path.endsWith('graphical_editor-windows.zip');

Widget _app(Locale locale) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => DownloadsDialog.show(context, probe: _probe),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  group('downloadUri', () {
    test('resolves a relative base against the page origin', () {
      final uri = downloadUri('/downloads', 'graphical_editor-web.zip');
      expect(uri.path, '/downloads/graphical_editor-web.zip');
    });

    test('keeps an absolute base untouched', () {
      final uri = downloadUri('https://cdn.example.com/clients', 'app.apk');
      expect(uri.scheme, 'https');
      expect(uri.host, 'cdn.example.com');
      expect(uri.path, '/clients/app.apk');
    });

    test('does not double the slash for a trailing-slash base', () {
      final uri = downloadUri('https://cdn.example.com/clients/', 'app.apk');
      expect(uri.path, '/clients/app.apk');
    });
  });

  testWidgets('downloads dialog enables only available clients (English)',
      (tester) async {
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Download client'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Soon'), findsNWidgets(downloadTargets.length - 1));
  });

  testWidgets('downloads dialog is localized when the locale is Russian',
      (tester) async {
    await tester.pumpWidget(_app(const Locale('ru')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Скачать клиент'), findsOneWidget);
    expect(find.text('Скачать'), findsOneWidget);
    expect(find.text('Скоро'), findsNWidgets(downloadTargets.length - 1));
  });
}