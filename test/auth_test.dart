import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/io/local_store.dart';

import 'test_doubles.dart';

void main() {
  group('Auth', () {
    late InMemoryKeyValueStore keyValueStore;
    late FakeApiClient api;
    late EditorController controller;

    EditorController build() => EditorController(
          storage: InMemoryProjectStorage(),
          tokenStore: keyValueStore,
          api: api,
        );

    setUp(() {
      keyValueStore = InMemoryKeyValueStore();
      api = FakeApiClient();
      controller = build();
    });

    test('init with no stored token shows the login screen', () async {
      await controller.initAuth();
      await _settle(() => controller.authStatus != AuthStatus.loading);
      expect(controller.authStatus, AuthStatus.signedOut);
      expect(controller.signedIn, isFalse);
      expect(controller.editorVisible, isFalse);
    });

    test('register signs the user in and stores the token', () async {
      await controller.register('a@b.com', 'secret1');
      expect(controller.authStatus, AuthStatus.signedIn);
      expect(controller.userEmail, 'a@b.com');
      expect(await keyValueStore.read('auth_token'), isNotNull);
      expect(await keyValueStore.read('auth_email'), 'a@b.com');
    });

    test('signIn accepts correct credentials', () async {
      api.seedUser('a@b.com', 'secret1');
      await controller.signIn('a@b.com', 'secret1');
      expect(controller.authStatus, AuthStatus.signedIn);
      expect(controller.userEmail, 'a@b.com');
    });

    test('signIn rejects wrong credentials and keeps the login screen',
        () async {
      api.seedUser('a@b.com', 'secret1');
      await controller.signIn('a@b.com', 'wrong1');
      expect(controller.authStatus, AuthStatus.signedOut);
      expect(controller.authError, isNotNull);
    });

    test('signOut clears the session', () async {
      await controller.register('a@b.com', 'secret1');
      await controller.signOut();
      expect(controller.authStatus, AuthStatus.signedOut);
      expect(await keyValueStore.read('auth_token'), isNull);
    });

    test('the editor is inaccessible without an account', () async {
      await controller.initAuth();
      await _settle(() => controller.authStatus != AuthStatus.loading);
      expect(controller.authStatus, AuthStatus.signedOut);
      expect(controller.editorVisible, isFalse);
    });

    test('restores a valid session from the stored token', () async {
      api.seedUser('a@b.com', 'secret1');
      await _loginAndGetToken(api, keyValueStore);
      controller = build();
      await _settle(() => controller.authStatus != AuthStatus.loading);
      expect(controller.authStatus, AuthStatus.signedIn);
      expect(controller.userEmail, 'a@b.com');
    });

    test('invalid stored token forces re-login', () async {
      await keyValueStore.write('auth_token', 'expired-token');
      await keyValueStore.write('auth_email', 'x@y.z');
      controller = build();
      await _settle(() => controller.authStatus != AuthStatus.loading);
      expect(controller.authStatus, AuthStatus.signedOut);
      expect(await keyValueStore.read('auth_token'), isNull);
    });

    test('edits while signed in are pushed to the server', () async {
      await controller.register('a@b.com', 'secret1');
      controller.createProject(name: 'Cloud');
      await controller.flushAutosave;
      final remote = api.workspaceFor('a@b.com');
      expect(remote, isNotNull);
      expect(remote, contains('Cloud'));
    });

    test('migration: first login uploads existing local projects', () async {
      controller.createProject(name: 'LocalOnly');
      await controller.flushAutosave;
      await controller.register('mig@b.com', 'secret1');
      await controller.flushAutosave;
      expect(api.workspaceFor('mig@b.com'), contains('LocalOnly'));
    });

    test('server is authoritative when the account already has projects',
        () async {
      final remoteJson = jsonEncode(<String, dynamic>{
        'version': 1,
        'projects': [
          <String, dynamic>{
            'id': '1',
            'name': 'Remote',
            'package': 'com.remote',
            'mainClass': 'MainApp',
            'description': '',
            'scenes': [
              <String, dynamic>{
                'name': 'main',
                'fxml': '<AnchorPane/>',
                'controller': 'com.remote.MainAppController',
              },
            ],
          },
        ],
      });
      api.seedUser('r@b.com', 'secret1', workspaceJson: remoteJson);
      await controller.register('local@first.com', 'secret1');
      controller.createProject(name: 'Local');
      await controller.flushAutosave;

      final second = EditorController(
        storage: InMemoryProjectStorage(),
        tokenStore: keyValueStore,
        api: api,
      );
      await _settle(() => second.authStatus != AuthStatus.loading);
      await second.signIn('r@b.com', 'secret1');
      expect(second.projects.single.name, 'Remote');
      expect(second.projects.length, 1);
    });
  });
}

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 20; i++) {
    if (done()) return;
    await Future<void>.delayed(Duration.zero);
  }
}

Future<String> _loginAndGetToken(
    FakeApiClient api, KeyValueStore store) async {
  final login = await api.login('a@b.com', 'secret1');
  expect(login.isOk, isTrue);
  await store.write('auth_token', login.value!.token);
  await store.write('auth_email', login.value!.email);
  return login.value!.email;
}