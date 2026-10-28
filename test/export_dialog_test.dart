import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:graphical_editor/l10n/app_localizations.dart';
import 'package:graphical_editor/project/project_exporter.dart';
import 'package:graphical_editor/ui/widgets/export_dialog.dart';

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
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final options = await showExportDialog(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${options?.format.extension}/${options?.buildTool.name}',
                    ),
                  ),
                );
              }
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the dialog defaults to a zip with Java sources', (tester) async {
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();
    await _openDialog(tester);

    expect(find.text('Export project'), findsOneWidget);
    expect(find.text('ZIP'), findsOneWidget);
    expect(find.text('TAR + GZIP'), findsOneWidget);
    expect(find.text('Build tool'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();

    expect(find.text('zip/maven'), findsOneWidget);
  });

  testWidgets('the build tool can be changed', (tester) async {
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();
    await _openDialog(tester);

    expect(find.text('Maven'), findsOneWidget);
    await tester.ensureVisible(find.text('Gradle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gradle'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Export'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();

    expect(find.text('zip/gradle'), findsOneWidget);
  });

  testWidgets('tar.gz can be selected and Java sources excluded',
      (tester) async {
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();
    await _openDialog(tester);

    await tester.tap(find.text('TAR + GZIP'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();

    expect(find.text('tar.gz/maven'), findsOneWidget);
  });

  testWidgets('cancelling returns no options', (tester) async {
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();
    await _openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('null/null'), findsOneWidget);
  });

  testWidgets('the dialog is translated', (tester) async {
    await tester.pumpWidget(_app(const Locale('ru')));
    await tester.pumpAndSettle();
    await _openDialog(tester);

    expect(find.text('Экспорт проекта'), findsOneWidget);
    expect(find.text('Формат архива'), findsOneWidget);
    expect(find.text('Сборочная система'), findsOneWidget);
    expect(find.text('Maven'), findsOneWidget);
    expect(find.text('Gradle'), findsOneWidget);
    expect(find.text('Включить Java-исходники'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Экспорт'), findsOneWidget);
  });

  test('export options carry the chosen format', () {
    const options = ExportOptions(format: ExportArchiveFormat.tarGz);
    expect(options.format.mimeType, 'application/gzip');
    expect(ExportArchiveFormat.zip.mimeType, 'application/zip');
  });
}