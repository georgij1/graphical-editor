import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/l10n/app_localizations.dart';
import 'package:graphical_editor/ui/editor_page.dart';
import 'package:graphical_editor/ui/widgets/status_bar.dart';
import 'package:graphical_editor/ui/widgets/user_avatar.dart';

import 'test_doubles.dart';

Widget _app(EditorController controller) {
  return ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      locale: controller.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: EditorPage(controller: controller),
    ),
  );
}

void main() {
  testWidgets('the selected language is persisted and applied on login',
      (tester) async {
    final store = InMemoryKeyValueStore();
    await store.write('app_lang', 'ru');
    final controller = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: store,
      api: FakeApiClient(),
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('Войти'), findsWidgets);
    expect(find.text('Создать аккаунт'), findsWidgets);
    expect(find.text('Эл. почта'), findsOneWidget);
    expect(find.text('Sign in to store your projects in the cloud.'),
        findsNothing);
  });

  testWidgets('switching the language in settings updates the UI',
      (tester) async {
    final controller = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: InMemoryKeyValueStore(),
      api: FakeApiClient(),
    );
    await controller.register('a@b.com', 'secret1');
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

// No project yet: the status bar is hidden entirely.
    expect(find.byType(StatusBar), findsNothing);

    controller.createProject(
      name: 'P',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpAndSettle();
    expect(find.byType(StatusBar), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);

    await tester.tap(find.byType(UserAvatar).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Interface language'), findsOneWidget);
    await tester.tap(find.text('Русский'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(controller.isRussian, isTrue);
    // The dialog itself is translated immediately.
    expect(find.text('Язык интерфейса'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);

    await tester.tap(find.text('Закрыть'), warnIfMissed: false);
    await tester.pumpAndSettle();

    final statusBar = find.byType(StatusBar);
    // The Canvas/Code switch now lives in the footer, so the translation is
    // checked there. A segment may build its label more than once, hence
    // findsWidgets.
    expect(find.descendant(of: statusBar, matching: find.textContaining('Холст')),
        findsWidgets);
    expect(
        find.descendant(of: statusBar, matching: find.textContaining('Canvas')),
        findsNothing);
    expect(find.text('Сохранено'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('the chosen language survives a restart', (tester) async {
    final store = InMemoryKeyValueStore();
    final controller = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: store,
      api: FakeApiClient(),
    );
    await controller.setLanguage('ru');

    final restarted = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: store,
      api: FakeApiClient(),
    );
    await tester.pumpWidget(_app(restarted));
    await tester.pumpAndSettle();

    expect(restarted.isRussian, isTrue);
    expect(find.text('Войти'), findsWidgets);
  });
}