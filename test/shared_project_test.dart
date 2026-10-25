import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';

import 'test_doubles.dart';

void main() {
  group('Shared project', () {
    late InMemoryProjectStorage storage;
    late InMemoryKeyValueStore keyValueStore;
    late FakeApiClient api;
    late EditorController controller;

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

    test('the owner publishes the project and it becomes shared', () async {
      api.seedUser('owner@mail.ru', 'pass');
      await controller.signIn('owner@mail.ru', 'pass');
      controller.createProject(name: 'Общий проект');
      final project = controller.projects.single;

      final ok = await controller.publishSharedProject();

      expect(ok, isTrue);
      expect(project.shared, isTrue);
      expect(api.sharedProjects.containsKey(project.id), isTrue);
      // The saved copy carries the owner.
      final saved = api.sharedProjects[project.id]!;
      expect(saved.ownerId, 'usr_owner@mail.ru');
      expect(saved.ownerEmail, 'owner@mail.ru');
    });

    test('a participant is added and removed', () async {
      api.seedUser('owner@mail.ru', 'pass');
      await controller.signIn('owner@mail.ru', 'pass');
      controller.createProject(name: 'Общий проект');
      await controller.publishSharedProject();

      final added = await controller.inviteCollaborator('guest@mail.ru', 'editor');
      expect(added, isTrue);
      expect(controller.collaborators.map((m) => m.email), contains('guest@mail.ru'));
      expect(controller.collaborativeMode, isTrue);

      final removed = await controller.removeCollaborator('guest@mail.ru');
      expect(removed, isTrue);
      expect(controller.collaborators, isEmpty);
    });

    test('the invited participant sees the project in the picker', () async {
      api.seedUser('owner@mail.ru', 'pass');
      final owner = EditorController(
        storage: InMemoryProjectStorage(),
        tokenStore: InMemoryKeyValueStore(),
        api: api,
      );
      await owner.signIn('owner@mail.ru', 'pass');
      owner.createProject(name: 'Общий проект');
      await owner.publishSharedProject();
      // The owner invites the guest.
      await owner.inviteCollaborator('guest@mail.ru', 'editor');
      final projectId = owner.projects.single.id;

      api.seedUser('guest@mail.ru', 'pass');
      final guest = EditorController(
        storage: InMemoryProjectStorage(),
        tokenStore: InMemoryKeyValueStore(),
        api: api,
      );
      await guest.signIn('guest@mail.ru', 'pass');
      await guest.loadSharedProjects();

      // The project is not in the personal workspace of the guest...
      expect(guest.projects, isEmpty);
      // ...but it is offered in the picker.
      expect(guest.allProjects.map((p) => p.id), contains(projectId));
      expect(guest.allProjects.single.collaborative, isTrue);
    });

    test('the viewer may open the project but the owner decides who joins',
        () async {
      api.seedUser('owner@mail.ru', 'pass');
      final owner = EditorController(
        storage: InMemoryProjectStorage(),
        tokenStore: InMemoryKeyValueStore(),
        api: api,
      );
      await owner.signIn('owner@mail.ru', 'pass');
      owner.createProject(name: 'Общий проект');
      final project = owner.projects.single;
      await owner.publishSharedProject();
      await owner.inviteCollaborator('guest@mail.ru', 'viewer');

      // The invited person opens the shared project.
      api.seedUser('guest@mail.ru', 'pass');
      final guest = EditorController(
        storage: InMemoryProjectStorage(),
        tokenStore: InMemoryKeyValueStore(),
        api: api,
      );
      await guest.signIn('guest@mail.ru', 'pass');
      await guest.loadSharedProjects();
      final shared = guest.allProjects.first;
      guest.openProject(shared);
      expect(guest.collaborativeMode, isTrue);
      expect(guest.collaborators.map((m) => m.email), contains('guest@mail.ru'));

      // The guest tries to add somebody else: the server refuses it, because
      // only the owner may invite people.
      final before = project.members.length;
      await guest.inviteCollaborator('third@mail.ru', 'editor');
      expect(project.members.length, before);
    });
  });
}
