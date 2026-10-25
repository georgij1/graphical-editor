import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/build/build_client.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/project/project_history.dart';

import 'test_doubles.dart';

/// A build service that always succeeds.
class _OkBuildClient extends BuildClient {
  _OkBuildClient() : super(httpClient: null);

  /// How many times the build service was asked to compile.
  int calls = 0;

  @override
  Future<BuildArtifact> build(Uint8List archive, {required bool bundle}) async {
    calls++;
    return BuildArtifact(fileName: 'app.jar', bytes: Uint8List.fromList([1, 2, 3]));
  }
}

void main() {
  group('Version and build history', () {
    late InMemoryProjectStorage storage;
    late InMemoryKeyValueStore keyValueStore;
    late FakeApiClient api;

    setUp(() {
      storage = InMemoryProjectStorage();
      keyValueStore = InMemoryKeyValueStore();
      api = FakeApiClient();
    });

    test('a build releases a version and is written into the history',
        () async {
      api.seedUser('owner@mail.ru', 'pass');
      final controller = EditorController(
        storage: storage,
        tokenStore: keyValueStore,
        api: api,
        buildClient: _OkBuildClient(),
      );
      await controller.signIn('owner@mail.ru', 'pass');
      controller.createProject(name: 'Общий проект');
      final project = controller.projects.single;

      // The build service is asked to save the file, so the file service is
      // replaced with one that only remembers the call.
      await controller.buildProject(
        project,
        bundle: false,
        releaseNotes: 'Добавлена главная сцена',
      );

      final history = controller.history;
      expect(history.versions, isNotEmpty);
      expect(history.versions.first.summary, 'Добавлена главная сцена');
      expect(history.versions.first.author, 'owner@mail.ru');
      expect(history.builds, isNotEmpty);
      expect(history.builds.first.succeeded, isTrue);
      expect(history.builds.first.artifact, 'app.jar');
      expect(history.builds.first.version, history.versions.first.revision);
    });

    test('the build runs even when the project cannot be published',
        () async {
      // Nobody is signed in, so there is no server to keep the history in.
      final buildClient = _OkBuildClient();
      final controller = EditorController(
        storage: storage,
        tokenStore: keyValueStore,
        api: api,
        buildClient: buildClient,
      );
      await controller.loadWorkspace();
      controller.createProject(name: 'Локальный проект');

      await controller.buildProject(
        controller.projects.single,
        bundle: false,
      );

      // The build service was called and the history stayed empty.
      expect(buildClient.calls, 1);
      expect(controller.history.versions, isEmpty);
      expect(controller.history.builds, isEmpty);
    });

    test('the history is read from the server', () async {
      api.seedUser('owner@mail.ru', 'pass');
      final controller = EditorController(
        storage: storage,
        tokenStore: keyValueStore,
        api: api,
      );
      await controller.signIn('owner@mail.ru', 'pass');
      controller.createProject(name: 'Общий проект');
      final project = controller.projects.single;
      await controller.publishSharedProject();

      // The owner has already released a version.
      await controller.createInviteLink('editor');
      api.histories[project.id] = ProjectHistory(
        projectId: project.id,
        versions: <ProjectVersion>[
          ProjectVersion(
            revision: 1,
            date: DateTime.utc(2026, 1, 1),
            author: 'owner@mail.ru',
            summary: 'Первая версия',
          ),
        ],
        builds: <BuildRecord>[
          BuildRecord(
            id: 'b1',
            version: 1,
            date: DateTime.utc(2026, 1, 1),
            author: 'owner@mail.ru',
            status: 'ok',
            artifact: 'app.jar',
            durationMs: 2500,
          ),
        ],
      );

      final history = await controller.loadHistory(project);

      expect(history.versions, hasLength(1));
      expect(history.builds, hasLength(1));
      expect(history.latestVersion?.revision, 1);
      // The project has not changed since the release.
      expect(history.isDirty(project.revision), isFalse);
    });
  });
}
