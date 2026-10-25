import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/editor/fx_catalog.dart';
import 'package:graphical_editor/project/java_generator.dart';
import 'package:graphical_editor/project/project.dart';

import 'test_doubles.dart';

void main() {
  group('ProjectWorkspace', () {
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

    test('starts with an empty workspace until load completes', () async {
      expect(controller.projectsLoaded, isFalse);
      await controller.loadWorkspace();
      expect(controller.projectsLoaded, isTrue);
      expect(controller.projects, isEmpty);
    });

    test('createProject builds a runnable scene with a controller', () {
      controller.createProject(
        name: 'Demo',
        package: 'com.acme.demo',
        mainClass: 'MainApp',
      );
      expect(controller.projects.length, 1);
      final project = controller.projects.single;
      expect(project.name, 'Demo');
      expect(project.mainClass, 'MainApp');
      expect(project.scenes.length, 1);
      final scene = project.mainScene!;
      expect(scene.name, 'main');
      expect(scene.controllerClass, 'com.acme.demo.MainAppController');
      expect(controller.currentProject, project);
      expect(controller.activeScene, scene);
      expect(controller.root.attributes['fx:controller'],
          'com.acme.demo.MainAppController');
    });

    test('project name and main class fall back to defaults', () {
      controller.createProject(name: '  ', mainClass: '  ');
      final project = controller.projects.single;
      expect(project.name, 'Untitled');
      expect(project.mainClass, 'MainApp');
    });

    test('edits are flushed into the active scene and persisted', () async {
      controller.createProject(name: 'P');
      final scene = controller.activeScene!;
      controller.addComponent(FxCatalog.lookup('Button')!);
      controller.setAttribute(controller.selected!, 'text', 'Hi');
      await controller.flushAutosave;
      expect(scene.fxml, contains('Hi'));
      expect(storage.data, contains('"name":"P"'));
      expect(storage.writes, greaterThan(0));
    });

    test('openScene loads a different scene and clears undo', () async {
      controller.createProject(name: 'P');
      controller.addComponent(FxCatalog.lookup('Label')!);
      expect(controller.canUndo, isTrue);
      controller.newScene('helper');
      expect(controller.projects.single.scenes.length, 2);
      final helper = controller.activeScene!;
      expect(helper.name, 'helper');
      expect(controller.canUndo, isFalse);
      controller.openScene(helper);
      expect(controller.activeScene, helper);
    });

    test('scene modifications do not leak into other scenes', () async {
      controller.createProject(name: 'P');
      final mainScene = controller.projects.single.scenes.first;
      controller.newScene('second');
      controller.addComponent(FxCatalog.lookup('Button')!);
      controller.newScene('third');
      await controller.flushAutosave;
      expect(mainScene.fxml, isNot(contains('>Button<')));
    });

    test('renameScene and deleteScene update the project', () {
      controller.createProject(name: 'P');
      controller.newScene('other');
      final project = controller.projects.single;
      final other =
          project.scenes.firstWhere((s) => s.name == 'other');
      controller.renameScene(other, 'renamed');
      expect(project.scenes.any((s) => s.name == 'renamed'), isTrue);
      controller.deleteScene(other);
      expect(project.scenes.length, 1);
      expect(project.scenes.single.name, 'main');
    });

    test('workspace round-trips through storage', () async {
      controller.createProject(name: 'Persist', mainClass: 'App');
      controller.newScene('two');
      await controller.flushAutosave;

      final reloaded = EditorController(
        storage: storage,
        tokenStore: keyValueStore,
        api: api,
      );
      await reloaded.loadWorkspace();
      expect(reloaded.projects.length, 1);
      final restored = reloaded.projects.single;
      expect(restored.name, 'Persist');
      expect(restored.mainClass, 'App');
      expect(restored.scenes.length, 2);
    });

    test('duplicate and delete project', () {
      controller.createProject(name: 'A');
      final original = controller.projects.single;
      controller.duplicateProject(original);
      expect(controller.projects.length, 2);
      expect(controller.projects.last.name, 'A copy');
      controller.deleteProject(controller.projects.last);
      expect(controller.projects.length, 1);
    });

    test('backToProjects keeps the editor document intact', () {
      controller.createProject(name: 'A');
      controller.addComponent(FxCatalog.lookup('TextField')!);
      controller.backToProjects();
      expect(controller.currentProject, isNull);
      expect(controller.activeScene, isNull);
      expect(controller.root.children.any((c) => c.tag == 'TextField'), isTrue);
    });
  });

  group('Project model', () {
    test('mainScene prefers the scene named main', () {
      final project = Project(
        id: '1',
        name: 'P',
        package: 'x',
        mainClass: 'MainApp',
        scenes: [
          SceneFile(name: 'other', fxml: ''),
          SceneFile(name: 'main', fxml: ''),
        ],
      );
      expect(project.mainScene!.name, 'main');
    });

    test('Project copies are deep', () {
      final project = Project(id: '1', name: 'P', package: 'x', mainClass: 'M')
        ..scenes.add(SceneFile(name: 's', fxml: '<x/>'));
      final copy = project.copy();
      copy.scenes.first.name = 'changed';
      expect(project.scenes.first.name, 's');
    });
  });

  group('JavaGenerator', () {
    test('emits the Application launcher and per-scene controllers', () {
      final project = Project(
        id: '1',
        name: 'Demo',
        package: 'com.acme.demo',
        mainClass: 'MainApp',
        scenes: [
          SceneFile(
            name: 'main',
            fxml: '',
            controllerClass: 'com.acme.demo.MainAppController',
          ),
          SceneFile(
            name: 'settings',
            fxml: '',
            controllerClass: 'com.acme.demo.SettingsController',
          ),
        ],
      );
      final files = JavaGenerator.generate(project);
      expect(files.map((f) => f.path), <String>[
        'src/main/java/com/acme/demo/MainApp.java',
        'src/main/java/com/acme/demo/MainAppController.java',
        'src/main/java/com/acme/demo/SettingsController.java',
      ]);
      final mainApp = files.first.content;
      expect(mainApp, contains('public class MainApp extends Application'));
      expect(mainApp, contains('getClass().getResource("main.fxml")'));
      expect(mainApp, contains('package com.acme.demo;'));
    });
  });
}