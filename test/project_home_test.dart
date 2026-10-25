import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/l10n/app_localizations.dart';
import 'package:graphical_editor/project/project_exporter.dart';
import 'package:graphical_editor/ui/widgets/project_home.dart';

import 'test_doubles.dart';

Widget _app(EditorController controller, {Locale locale = const Locale('en')}) {
  return ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: ProjectHome(controller: controller)),
    ),
  );
}

Future<EditorController> _withProjects(int count) async {
  final controller = EditorController(
    storage: InMemoryProjectStorage(),
    tokenStore: InMemoryKeyValueStore(),
    api: FakeApiClient(),
  );
  await controller.register('a@b.com', 'secret1');
  for (var i = 1; i <= count; i++) {
    controller.createProject(
      name: 'Project $i',
      package: 'com.example.p$i',
      mainClass: 'MainApp',
    );
  }
  return controller;
}

/// A laptop-sized window: the page size is derived from it at runtime.
void _surface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Reads "Projects 1–N of M" back so the assertions do not hardcode the
/// number of cards that happens to fit.
int _perPage(WidgetTester tester) {
  final label = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .whereType<String>()
      .firstWhere((data) => data.contains(' of '));
  return int.parse(RegExp(r'([0-9]+) of').firstMatch(label)!.group(1)!);
}

Future<void> _nextPage(WidgetTester tester) async {
  final next = find.byIcon(Icons.chevron_right);
  await tester.ensureVisible(next);
  await tester.pumpAndSettle();
  await tester.tap(next, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a list that fits shows no pagination', (tester) async {
    _surface(tester);
    final controller = await _withProjects(3);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('Project 1'), findsOneWidget);
    expect(find.text('Project 3'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.textContaining(' of '), findsNothing);
  });

  testWidgets('the card opens a settings window instead of a menu',
      (tester) async {
    _surface(tester);
    final controller = await _withProjects(3);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    // No overflow menu and no text label on the card: just the icon.
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNWidgets(3));

    await tester.tap(find.byIcon(Icons.settings_outlined).first,
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Project settings'), findsOneWidget);
    expect(find.text('Open project'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('the page holds as many cards as the window fits',
      (tester) async {
    _surface(tester);
    final controller = await _withProjects(20);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final perPage = _perPage(tester);
    expect(perPage, greaterThan(1));

    // The last card of the page is visible, the next one is not.
    expect(find.text('Project $perPage'), findsOneWidget);
    expect(find.text('Project ${perPage + 1}'), findsNothing);

    // Nothing scrolls: the picker fills the window exactly.
    final scrollables = find.byType(Scrollable);
    expect(scrollables, findsNothing);
  });

  testWidgets('moving between pages swaps the visible projects',
      (tester) async {
    _surface(tester);
    final controller = await _withProjects(20);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final perPage = _perPage(tester);
    expect(find.text('1 / ${(20 / perPage).ceil()}'), findsOneWidget);

    await _nextPage(tester);

    expect(find.text('2 / ${(20 / perPage).ceil()}'), findsOneWidget);
    expect(find.text('Project 1'), findsNothing);
    expect(find.text('Project ${perPage + 1}'), findsOneWidget);

    // The last page has no "next" control.
    for (var page = 3; page <= (20 / perPage).ceil(); page++) {
      await _nextPage(tester);
    }
    final next = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      ),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('picking a project opens it', (tester) async {
    _surface(tester);
    final controller = await _withProjects(20);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final perPage = _perPage(tester);
    await _nextPage(tester);
    await tester.tap(find.text('Project ${perPage + 1}'));
    await tester.pumpAndSettle();

    expect(controller.currentProject?.name, 'Project ${perPage + 1}');
  });

  testWidgets('removing projects can move the view back a page',
      (tester) async {
    _surface(tester);
    final controller = await _withProjects(20);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final perPage = _perPage(tester);
    final pages = (20 / perPage).ceil();

    // Jump to the last page and delete its single project.
    for (var page = 2; page <= pages; page++) {
      await _nextPage(tester);
    }
    expect(find.text('$pages / $pages'), findsOneWidget);

    final last = 'Project ${(pages - 1) * perPage + 1}';
    expect(find.text(last), findsOneWidget);

    // Deleting only lives in the settings window now.
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    await tester.tap(find.byIcon(Icons.settings_outlined).last,
        warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(controller.projects.length, 19);
    expect(find.text('$pages / ${(19 / perPage).ceil()}'), findsOneWidget);
  });

  testWidgets('the pagination sits right below the cards', (tester) async {
    _surface(tester);
    final controller = await _withProjects(20);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final perPage = _perPage(tester);
    if ((20 / perPage).ceil() < 2) return; // everything fits on one page

    // Bottom of the last card and top of the pager must be neighbours.
    final cardsBottom = tester.getBottomLeft(find.byType(Card).last).dy;
    final pagerTop =
        tester.getTopLeft(find.byIcon(Icons.chevron_left)).dy;
    expect(pagerTop - cardsBottom, lessThan(24));
  });

  testWidgets('the description can be edited in the settings window',
      (tester) async {
    _surface(tester);
    final controller = await _withProjects(1);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined).first,
        warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Description'), 'Demo application');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(controller.projects.single.description, 'Demo application');
    expect(find.textContaining('Project updated'), findsOneWidget);

    // The description reaches the generated README of an exported project.
    final bytes = const ProjectExporter().build(
      controller.projects.single,
      const ExportOptions(),
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final readme = utf8.decode(
      archive.findFile('Project 1/README.md')!.content as List<int>,
    );
    expect(readme, contains('Demo application'));
  });

  testWidgets('the settings window is translated', (tester) async {
    _surface(tester);
    final controller = await _withProjects(1);
    await tester.pumpWidget(_app(controller, locale: const Locale('ru')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined).first,
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Настройки проекта'), findsOneWidget);
    expect(find.text('Название проекта'), findsOneWidget);
    expect(find.text('Описание'), findsOneWidget);
    expect(find.text('Действия'), findsOneWidget);
    expect(find.text('Открыть проект'), findsOneWidget);
  });

  testWidgets('the pagination is translated', (tester) async {
    _surface(tester);
    final controller = await _withProjects(20);
    await tester.pumpWidget(_app(controller, locale: const Locale('ru')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Проекты'), findsOneWidget);
    expect(find.textContaining(' из '), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(Tooltip),
      ).first,
    );
    expect(tooltip.message, 'Следующая страница');
  });
}