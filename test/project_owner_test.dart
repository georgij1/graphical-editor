import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/project/project.dart';
import 'package:graphical_editor/project/project_storage_base.dart';

import 'test_doubles.dart';

void main() {
  group('Project owner', () {
    late InMemoryProjectStorage storage;
    late InMemoryKeyValueStore keyValueStore;
    late FakeApiClient api;

    EditorController build() => EditorController(
          storage: storage,
          tokenStore: keyValueStore,
          api: api,
        );

    setUp(() {
      storage = InMemoryProjectStorage();
      keyValueStore = InMemoryKeyValueStore();
      api = FakeApiClient();
    });

    test('a project made without a sign-in belongs to the guest scope', () async {
      final controller = build();
      await controller.loadWorkspace();
      controller.createProject(name: 'Черновик');
      await controller.flushAutosave;

      final project = controller.projects.single;
      expect(project.ownerId, isNull);
      expect(project.ownerEmail, isNull);
      // The work of a guest stays in the guest slot of the local storage.
      expect(storage.scopes.containsKey(guestScope), isTrue);
    });

    test('after signing in the guest projects become the property of the account',
        () async {
      final controller = build();
      await controller.loadWorkspace();
      controller.createProject(name: 'Черновик');
      await controller.flushAutosave;

      api.seedUser('ivanov@mail.ru', 'pass');
      await controller.signIn('ivanov@mail.ru', 'pass');
      await controller.flushAutosave;

      final project = controller.projects.single;
      expect(project.ownerId, 'usr_ivanov@mail.ru');
      expect(project.ownerEmail, 'ivanov@mail.ru');
      // The account owns the project in the cloud as well.
      expect(api.workspaceFor('ivanov@mail.ru'), isNotNull);
      final cloud = WorkspaceData.fromJson(
          jsonDecode(api.workspaceFor('ivanov@mail.ru')!) as Map<String, dynamic>);
      expect(cloud.projects.single.ownerId, 'usr_ivanov@mail.ru');
    });

    test('every account keeps its own projects', () async {
      api.seedUser('ivanov@mail.ru', 'pass');
      api.seedUser('petrov@mail.ru', 'pass');

      final first = build();
      await first.loadWorkspace();
      await first.signIn('ivanov@mail.ru', 'pass');
      first.createProject(name: 'Проект Иванова');
      await first.flushAutosave;

      final second = build();
      await second.loadWorkspace();
      await second.signIn('petrov@mail.ru', 'pass');

      // The second account does not see the projects of the first one.
      expect(second.projects.map((p) => p.name), isNot(contains('Проект Иванова')));

      second.createProject(name: 'Проект Петрова');
      await second.flushAutosave;

      final firstAgain = build();
      await firstAgain.loadWorkspace();
      await firstAgain.signIn('ivanov@mail.ru', 'pass');
      expect(firstAgain.projects.map((p) => p.name),
          containsAll(<String>['Проект Иванова']));
      expect(firstAgain.projects.map((p) => p.name),
          isNot(contains('Проект Петрова')));
    });

    test('signing out hides the projects of the account', () async {
      api.seedUser('ivanov@mail.ru', 'pass');
      final controller = build();
      await controller.loadWorkspace();
      await controller.signIn('ivanov@mail.ru', 'pass');
      controller.createProject(name: 'Проект Иванова');
      await controller.flushAutosave;
      expect(controller.projects.length, 1);

      await controller.signOut();

      // The list is empty again; the projects stay in the account's slot.
      expect(controller.projects, isEmpty);
      expect(storage.scopes.containsKey('usr_ivanov@mail.ru'), isTrue);
    });

    test('a project of another account is never taken over', () {
      final project = Project(
        id: 'p1',
        name: 'Чужой',
        package: 'com.example',
        mainClass: 'MainApp',
        ownerId: 'usr_petrov@mail.ru',
        ownerEmail: 'petrov@mail.ru',
      );

      project.assignOwner('usr_ivanov@mail.ru', 'ivanov@mail.ru');

      expect(project.ownerId, 'usr_petrov@mail.ru');
      expect(project.ownerEmail, 'petrov@mail.ru');
      expect(project.belongsTo('usr_ivanov@mail.ru'), isFalse);
    });

    test('the owner survives saving and loading the project', () async {
      final controller = build();
      await controller.loadWorkspace();
      controller.createProject(name: 'С владельцем');
      final project = controller.projects.single;
      project.assignOwner('usr_ivanov@mail.ru', 'ivanov@mail.ru');
      await controller.flushAutosave;

      final restored = Project.fromJson(
          jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>);
      expect(restored.ownerId, 'usr_ivanov@mail.ru');
      expect(restored.ownerEmail, 'ivanov@mail.ru');
    });
  });
}
