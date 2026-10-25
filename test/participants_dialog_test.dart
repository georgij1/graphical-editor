import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/l10n/app_localizations.dart';
import 'package:graphical_editor/project/project.dart';
import 'package:graphical_editor/ui/widgets/project_settings_dialog.dart';
import 'package:graphical_editor/ui/widgets/user_avatar.dart';

import 'test_doubles.dart';

void main() {
  testWidgets('the participants block looks as expected', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final storage = InMemoryProjectStorage();
    final keyValueStore = InMemoryKeyValueStore();
    final api = FakeApiClient();
    api.seedUser('owner@mail.ru', 'pass');
    api.seedUser('guest@mail.ru', 'pass');
    api.seedUser('petrov@mail.ru', 'pass');

    final controller = EditorController(
      storage: storage,
      tokenStore: keyValueStore,
      api: api,
    );
    await controller.signIn('owner@mail.ru', 'pass');
    await controller.loadAccounts();
    controller.createProject(name: 'Общий проект');
    final project = controller.projects.single;
    project.members.add(ProjectMember(email: 'guest@mail.ru', role: 'editor'));
    project.members.add(ProjectMember(email: 'petrov@mail.ru', role: 'viewer'));

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(
        body: ProjectSettingsDialog(controller: controller, project: project),
      ),
    ));
    await tester.pumpAndSettle();

    // The window shows the participants and the field to pick a new one.
    expect(find.text('Участники'), findsOneWidget);
    expect(find.text('guest@mail.ru'), findsOneWidget);
    expect(find.text('petrov@mail.ru'), findsOneWidget);
    expect(find.byType(UserAvatar), findsWidgets);
    expect(find.byType(Autocomplete<String>), findsOneWidget);

    // The list of the accounts opens with the accounts of the system.
    await tester.tap(find.byType(Autocomplete<String>));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'pet');
    await tester.pumpAndSettle();

    // The account of the system is offered in the list.
    expect(find.text('petrov@mail.ru'), findsWidgets);
  });

  testWidgets('the cross in the header closes the window', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final storage = InMemoryProjectStorage();
    final keyValueStore = InMemoryKeyValueStore();
    final api = FakeApiClient();
    api.seedUser('owner@mail.ru', 'pass');

    final controller = EditorController(
      storage: storage,
      tokenStore: keyValueStore,
      api: api,
    );
    await controller.signIn('owner@mail.ru', 'pass');
    controller.createProject(name: 'Общий проект');
    final project = controller.projects.single;

    var closed = false;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProjectSettingsDialog(
                context,
                controller: controller,
                project: project,
              ).then((_) => closed = true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The cross is in the header of the window, and the button at the bottom
    // is gone.
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Закрыть'), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(find.byType(Dialog), findsNothing);
  });
}
