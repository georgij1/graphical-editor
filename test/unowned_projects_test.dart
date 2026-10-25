import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';

import 'test_doubles.dart';

/// Puts a project without an owner into the storage of the account.
void seedUnownedProject(InMemoryProjectStorage storage, String scope) {
  storage.scopes[scope] = jsonEncode({
    'version': 1,
    'projects': [
      {
        'id': 'orphan-1',
        'name': 'Старый проект',
        'package': 'com.example',
        'mainClass': 'MainApp',
        'scenes': <dynamic>[],
      },
    ],
  });
}

void main() {
  group('Projects without an owner', () {
    late InMemoryProjectStorage storage;
    late InMemoryKeyValueStore keyValueStore;
    late FakeApiClient api;
    late EditorController controller;

    const owner = 'owner@mail.ru';
    const scope = 'usr_owner@mail.ru';

    setUp(() {
      storage = InMemoryProjectStorage();
      keyValueStore = InMemoryKeyValueStore();
      api = FakeApiClient();
      controller = EditorController(
        storage: storage,
        tokenStore: keyValueStore,
        api: api,
      );
    });

    test('the projects without an owner are told apart', () async {
      api.seedUser(owner, 'pass');
      await controller.signIn(owner, 'pass');
      controller.createProject(name: 'Мой проект');
      // A project of the previous versions: it has no owner. It appears after
      // the sign-in, so it is not claimed by the account.
      seedUnownedProject(storage, scope);
      await controller.loadWorkspace();

      final unowned = controller.unownedProjects
          .map((p) => p.name)
          .toList();

      expect(unowned, contains('Старый проект'));
      // The project without an owner is not shown in the picker.
      expect(controller.myProjects.map((p) => p.name),
          isNot(contains('Старый проект')));
    });

    test('binding takes the projects without an owner', () async {
      api.seedUser(owner, 'pass');
      await controller.signIn(owner, 'pass');
      seedUnownedProject(storage, scope);
      await controller.loadWorkspace();
      expect(controller.unownedProjects, hasLength(1));

      // The project without an owner is not shown in the picker.
      expect(controller.myProjects, isEmpty);
      expect(controller.allProjects.length, 1);
    });

    test('the project of another account is not bound', () async {
      api.seedUser(owner, 'pass');
      await controller.signIn(owner, 'pass');
      storage.scopes[scope] = jsonEncode({
        'version': 1,
        'projects': [
          {
            'id': 'foreign-1',
            'name': 'Чужой проект',
            'package': 'com.example',
            'mainClass': 'MainApp',
            'ownerId': 'usr_other@mail.ru',
            'ownerEmail': 'other@mail.ru',
            'scenes': <dynamic>[],
          },
        ],
      });
      await controller.loadWorkspace();

      // The project of somebody else is not shown either.
      expect(controller.myProjects, isEmpty);
      expect(controller.unownedProjects, isEmpty);
    });

    test('only the projects of the owner and of the participants are shown',
        () async {
      api.seedUser(owner, 'pass');
      await controller.signIn(owner, 'pass');
      storage.scopes[scope] = jsonEncode({
        'version': 1,
        'projects': [
          {
            'id': 'mine-1',
            'name': 'Мой проект',
            'package': 'com.example',
            'mainClass': 'MainApp',
            'ownerId': 'usr_owner@mail.ru',
            'ownerEmail': owner,
            'scenes': <dynamic>[],
          },
          {
            'id': 'shared-1',
            'name': 'Общий проект',
            'package': 'com.example',
            'mainClass': 'MainApp',
            'ownerId': 'usr_other@mail.ru',
            'ownerEmail': 'other@mail.ru',
            'members': [
              {'email': owner, 'role': 'editor'},
            ],
            'scenes': <dynamic>[],
          },
          {
            'id': 'foreign-1',
            'name': 'Чужой проект',
            'package': 'com.example',
            'mainClass': 'MainApp',
            'ownerId': 'usr_other@mail.ru',
            'ownerEmail': 'other@mail.ru',
            'scenes': <dynamic>[],
          },
        ],
      });
      await controller.loadWorkspace();

      final shown = controller.myProjects.map((p) => p.name).toList();

      // The own project and the one I take part in are shown...
      expect(shown, contains('Мой проект'));
      expect(shown, contains('Общий проект'));
      // ...the project of somebody else is not.
      expect(shown, isNot(contains('Чужой проект')));
    });
  });
}
