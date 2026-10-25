import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/project/invite_link_base.dart';

import 'test_doubles.dart';

/// A link reader that always reports the same invitation.
class _FakeInviteLinks implements InviteLinks {
  _FakeInviteLinks(this.pending);

  @override
  final Invite? pending;

  @override
  String build(String projectId, String token) =>
      'http://localhost:8080/#invite/$projectId/$token';
}

void main() {
  group('Invitation link', () {
    late InMemoryProjectStorage storage;
    late InMemoryKeyValueStore keyValueStore;
    late FakeApiClient api;

    setUp(() {
      storage = InMemoryProjectStorage();
      keyValueStore = InMemoryKeyValueStore();
      api = FakeApiClient();
    });

    EditorController build([Invite? pending]) => EditorController(
          storage: storage,
          tokenStore: keyValueStore,
          api: api,
          inviteLinks: _FakeInviteLinks(pending),
        );

    test('the owner creates a link for the project', () async {
      api.seedUser('owner@mail.ru', 'pass');
      final controller = build();
      await controller.signIn('owner@mail.ru', 'pass');
      controller.createProject(name: 'Общий проект');
      final project = controller.projects.single;

      final link = await controller.createInviteLink('editor');

      expect(link, isNotNull);
      expect(link, contains(project.id));
      expect(link, startsWith('http://localhost:8080/#invite/'));
      expect(controller.inviteLink, link);
    });

    test('the invited person joins the project with the link', () async {
      api.seedUser('owner@mail.ru', 'pass');
      final owner = build();
      await owner.signIn('owner@mail.ru', 'pass');
      owner.createProject(name: 'Общий проект');
      final project = owner.projects.single;
      final link = await owner.createInviteLink('editor');
      expect(link, isNotNull);

      // The token of the link is the last one the owner has issued.
      final token = api.inviteToken!;

      api.seedUser('guest@mail.ru', 'pass');
      final guest = build(Invite(projectId: project.id, token: token));
      await guest.signIn('guest@mail.ru', 'pass');

      final info = await guest.readPendingInvite();
      expect(info, isNotNull);
      expect(info!.projectName, 'Общий проект');
      expect(info.ownerEmail, 'owner@mail.ru');

      final joined = await guest.acceptInvite(
          Invite(projectId: project.id, token: token));
      expect(joined, isTrue);
      // The project is now in the workspace of the guest.
      expect(guest.myProjects.map((p) => p.name), contains('Общий проект'));
    });

    test('a wrong token does not open the project', () async {
      api.seedUser('guest@mail.ru', 'pass');
      final guest = build(
          const Invite(projectId: 'unknown', token: 'wrong-token'));
      await guest.signIn('guest@mail.ru', 'pass');

      final info = await guest.readPendingInvite();
      expect(info, isNull);

      final joined = await guest.acceptInvite(
          const Invite(projectId: 'unknown', token: 'wrong-token'));
      expect(joined, isFalse);
    });
  });
}
