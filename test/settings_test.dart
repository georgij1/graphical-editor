import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/l10n/app_localizations.dart';
import 'package:graphical_editor/ui/editor_page.dart';
import 'package:graphical_editor/ui/widgets/settings_dialog.dart';
import 'package:graphical_editor/ui/widgets/user_avatar.dart';

import 'test_doubles.dart';

Widget _app(EditorController controller) {
  return ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      locale: controller.locale,
      themeMode: switch (controller.themeSetting) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: EditorPage(controller: controller),
    ),
  );
}

Future<EditorController> _signedIn() async {
  final controller = EditorController(
    storage: InMemoryProjectStorage(),
    tokenStore: InMemoryKeyValueStore(),
    api: FakeApiClient(),
  );
  await controller.register('a@b.com', 'secret1');
  return controller;
}

void main() {
  testWidgets('the theme can be switched from the settings dialog',
      (tester) async {
    final controller = await _signedIn();
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(Theme.of(tester.element(find.byType(EditorPage))).brightness,
        Brightness.light);

    await tester.tap(find.byType(UserAvatar).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Theme'), findsOneWidget);

    await tester.tap(find.text('Dark'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(controller.isDarkTheme, isTrue);
    expect(Theme.of(tester.element(find.byType(EditorPage))).brightness,
        Brightness.dark);
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.text('Light'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(controller.isLightTheme, isTrue);
    expect(Theme.of(tester.element(find.byType(EditorPage))).brightness,
        Brightness.light);
  });

  testWidgets('the theme survives a restart', (tester) async {
    final store = InMemoryKeyValueStore();
    final controller = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: store,
      api: FakeApiClient(),
    );
    await controller.setTheme('dark');

    final restarted = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: store,
      api: FakeApiClient(),
    );
    await tester.pumpWidget(_app(restarted));
    await tester.pumpAndSettle();

    expect(restarted.isDarkTheme, isTrue);
    expect(Theme.of(tester.element(find.byType(EditorPage))).brightness,
        Brightness.dark);
  });

  testWidgets('theme options are translated', (tester) async {
    final store = InMemoryKeyValueStore();
    await store.write('app_lang', 'ru');
    final controller = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: store,
      api: FakeApiClient(),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSettingsDialog(context, controller: controller),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Тема'), findsOneWidget);
    expect(find.text('Как в системе'), findsOneWidget);
    expect(find.text('Светлая'), findsOneWidget);
    expect(find.text('Тёмная'), findsOneWidget);
  });
}