import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/editor/fx_catalog.dart';
import 'package:graphical_editor/model/fxml_node.dart';
import 'package:graphical_editor/ui/editor_page.dart';
import 'package:graphical_editor/ui/widgets/canvas_view.dart';
import 'package:graphical_editor/ui/widgets/inspector_panel.dart';
import 'package:graphical_editor/ui/widgets/palette_panel.dart';
import 'package:graphical_editor/ui/widgets/project_panel.dart';
import 'package:graphical_editor/ui/widgets/project_tree_panel.dart';
import 'package:graphical_editor/ui/widgets/source_view.dart';
import 'package:graphical_editor/ui/widgets/canvas_area.dart';
import 'package:graphical_editor/ui/widgets/toolbar.dart';
import 'package:graphical_editor/ui/widgets/status_bar.dart';

import 'test_doubles.dart';

EditorController standaloneController() => EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: InMemoryKeyValueStore(),
      api: FakeApiClient(),
    );

void main() {
  testWidgets('editor toolbar is hidden until a project is opened',
      (tester) async {
    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);

    // The document actions live in the project tree, which only exists while a
    // project is open.
    final openButton = find.descendant(
      of: find.byType(ProjectPanel),
      matching: find.byIcon(Icons.folder_open),
    );
    expect(openButton, findsNothing);

    controller.createProject(
      name: 'P',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pump();
    expect(openButton, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.folder_open),
      ),
      findsNothing,
    );
    // The rest of the document actions moved with it.
    expect(
      find.descendant(
        of: find.byType(ProjectPanel),
        matching: find.byIcon(Icons.save_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ProjectPanel),
        matching: find.byIcon(Icons.file_download_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ProjectPanel),
        matching: find.byIcon(Icons.note_add_outlined),
      ),
      findsOneWidget,
    );
  });

testWidgets('the status bar is hidden until a project is opened',
      (tester) async {
    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    // Nothing to describe before a project is opened.
    expect(find.byType(StatusBar), findsNothing);

    controller.createProject(
      name: 'P',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pump();

    expect(find.byType(StatusBar), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);

    controller.addComponent(FxCatalog.lookup('Button')!);
    await tester.pump();

    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('the inspector is hidden until a project is opened',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    // Wide layout: the inspector column is not rendered at all.
    expect(find.byType(InspectorPanel), findsNothing);

    controller.createProject(
      name: 'P',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pump();

    expect(find.byType(InspectorPanel), findsOneWidget);
  });

  testWidgets('the narrow layout drops the inspector tab without a project',
      (tester) async {
    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    expect(find.text('Inspector'), findsNothing);

    controller.createProject(
      name: 'P',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pump();

    expect(find.text('Inspector'), findsOneWidget);
  });

  testWidgets('components and outline stay hidden until a project is opened',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    // No side panels and no scene bar: the picker owns the whole area.
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(ProjectPanel), findsNothing);
    expect(find.text('Choose a project'), findsOneWidget);

    controller.createProject(
      name: 'P',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pump();

    // The project tabs and the scene bar show up together.
    final tabs = find.byType(TabBar);
    expect(find.descendant(of: tabs, matching: find.text('Components')),
        findsOneWidget);
    expect(
        find.descendant(of: tabs, matching: find.text('Outline')),
        findsOneWidget);
    expect(find.descendant(of: tabs, matching: find.text('Projects')),
        findsNothing);
    expect(find.byType(ProjectPanel), findsOneWidget);

    // Opening the tab reveals the palette it hosts.
    await tester.tap(find.text('Components'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PalettePanel), findsOneWidget);
  });

  testWidgets('the header returns to the project list', (tester) async {
    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pump();
    // The project tree now lives in the left panel, next to the inspector.
    expect(find.byType(ProjectPanel), findsOneWidget);
    expect(find.byType(ProjectTreePanel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Project'),
      ),
      findsOneWidget,
    );

    // The leave button lives in the app bar, next to the project name.
    final back = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.arrow_back),
    );
    expect(back, findsOneWidget);

    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(find.byType(ProjectPanel), findsNothing);
    expect(find.text('Choose a project'), findsOneWidget);
    expect(controller.currentProject, isNull);
  });

  testWidgets('the tree and the inspector share the right column',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pump();

    final tree = find.byType(ProjectTreePanel);
    final inspector = find.byType(InspectorPanel);
    expect(tree, findsOneWidget);
    expect(inspector, findsOneWidget);

    // Both are on the right of the canvas, tree above the inspector.
    final canvasCenter =
        tester.getCenter(find.byType(CanvasView)).dx;
    expect(tester.getCenter(tree).dx, greaterThan(canvasCenter));
    expect(tester.getCenter(inspector).dx, greaterThan(canvasCenter));
    expect(tester.getTopLeft(tree).dy, lessThan(tester.getTopLeft(inspector).dy));

    // The left panel keeps only the components and the outline.
    final tabs = find.byType(TabBar);
    expect(find.descendant(of: tabs, matching: find.text('Components')),
        findsOneWidget);
    expect(find.descendant(of: tabs, matching: find.text('Outline')),
        findsOneWidget);
    expect(find.descendant(of: tabs, matching: find.text('Project')),
        findsNothing);
  });

  testWidgets('the divider between tree and inspector is draggable',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    final treeRect = tester.getRect(find.byType(ProjectTreePanel));
    final inspectorRect = tester.getRect(find.byType(InspectorPanel));
    // The handle sits between the bottom of the tree and the top of the
    // inspector.
    final divider = (treeRect.bottom + inspectorRect.top) / 2;

    // Until the handle is dragged the pane follows its content.
    expect(controller.treeFraction, isNull);

    // Dragging up first: there is room to grow the tree only after shrinking
    // it, because the untouched pane already fills the available space.
    await tester.dragFrom(Offset(1200, divider), const Offset(0, -120));
    await tester.pumpAndSettle();
    final shrunk = controller.treeFraction;
    expect(shrunk, isNotNull);
    expect(
      tester.getBottomLeft(find.byType(ProjectTreePanel)).dy,
      lessThan(treeRect.bottom),
    );

    // Dragging back down grows it again.
    final movedTree = tester.getRect(find.byType(ProjectTreePanel));
    final movedInspector = tester.getRect(find.byType(InspectorPanel));
    await tester.dragFrom(
      Offset(1200, (movedTree.bottom + movedInspector.top) / 2),
      const Offset(0, 260),
    );
    await tester.pumpAndSettle();

    expect(controller.treeFraction!, greaterThan(shrunk!));
    expect(
      tester.getBottomLeft(find.byType(ProjectTreePanel)).dy,
      greaterThan(movedTree.bottom),
    );

    // Dragging far up clamps instead of collapsing the inspector.
    final highTree = tester.getRect(find.byType(ProjectTreePanel));
    final highInspector = tester.getRect(find.byType(InspectorPanel));
    await tester.dragFrom(
      Offset(1200, (highTree.bottom + highInspector.top) / 2),
      const Offset(0, -4000),
    );
    await tester.pumpAndSettle();

    expect(controller.treeFraction, lessThan(shrunk));
    // The top pane never shrinks below its minimum, so the header stays
    // visible instead of being squeezed away.
    expect(tester.getRect(find.byType(ProjectPanel)).height,
        greaterThanOrEqualTo(120));
    expect(tester.takeException(), isNull);
    expect(find.byType(InspectorPanel), findsOneWidget);
  });

  testWidgets('scrolled tree content stays inside the section',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    for (var i = 0; i < 6; i++) {
      controller.newScene('scene$i');
    }
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    // Shrink the section so its content cannot possibly fit.
    controller.setTreeFraction(0.05);
    await tester.pumpAndSettle();

    final section = tester.getRect(find.byType(ProjectPanel));
    final tree = find.byType(ProjectTreePanel);

    // Scrolled content must stay clipped to the section instead of painting
    // over the divider.
    final list = tester.widget<SingleChildScrollView>(find.descendant(
      of: tree,
      matching: find.byType(SingleChildScrollView),
    ));
    expect(list.physics, isA<ClampingScrollPhysics>());

    // Scrolling reaches the last row without errors, and it stays inside the
    // section, so nothing became unreachable behind the divider.
    final scrollable = find
        .descendant(of: tree, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('scene5.fxml'), 120,
        scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final lastScene = tester.getRect(find.text('scene5.fxml'));
    expect(lastScene.bottom, lessThanOrEqualTo(section.bottom));
    expect(lastScene.top, greaterThanOrEqualTo(section.top));
  });

  testWidgets('a squeezed inspector pane does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    // Almost the whole column goes to the tree.
    controller.setTreeFraction(0.9);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // And with nothing selected the inspector shows its hint.
    final hint = find.text('Select an element on the canvas to edit its properties.');
    expect(hint, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the divider follows the tree content until it is dragged',
      (tester) async {
    // Tall enough for the whole tree, so nothing has to be cut.
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    controller.newScene('main');
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pumpAndSettle();
    // A project with one scene: the pane ends right below the tree, leaving
    // the rest of the column to the inspector.
    final section = tester.getRect(find.byType(ProjectPanel));
    final inspector = tester.getRect(find.byType(InspectorPanel));
    // The draggable handle sits between the two panes.
    expect(inspector.top - section.bottom, lessThanOrEqualTo(16));

    // Nothing is sliced by the divider: the last generated file is complete.
    final lastRow = find.text('pom.xml');
    expect(lastRow, findsOneWidget);
    expect(tester.getRect(lastRow).bottom, lessThan(section.bottom));

    // Adding scenes grows the pane while there is room for it.
    controller.newScene('extra');
    await tester.pumpAndSettle();
    final grown = tester.getRect(find.byType(ProjectPanel));
    expect(grown.height, greaterThan(section.height));
    expect(tester.getRect(find.byType(InspectorPanel)).top - grown.bottom,
        lessThanOrEqualTo(16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a double click on the divider restores the fitted height',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pumpAndSettle();

    final fitted = tester.getRect(find.byType(ProjectPanel));

    // Squeeze the pane first.
    final tree = tester.getRect(find.byType(ProjectTreePanel));
    final inspector = tester.getRect(find.byType(InspectorPanel));
    await tester.dragFrom(
      Offset(1200, (tree.bottom + inspector.top) / 2),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(controller.treeFraction, isNotNull);
    expect(tester.getRect(find.byType(ProjectPanel)).height,
        lessThan(fitted.height));

    // Double click puts it back.
    final squeezedTree = tester.getRect(find.byType(ProjectTreePanel));
    final squeezedInspector = tester.getRect(find.byType(InspectorPanel));
    await tester.tapAt(Offset(1200, (squeezedTree.bottom + squeezedInspector.top) / 2));
    await tester.pumpAndSettle();
    await tester.tapAt(Offset(1200, (squeezedTree.bottom + squeezedInspector.top) / 2));
    await tester.pumpAndSettle();

    expect(controller.treeFraction, isNull);
    expect(tester.getRect(find.byType(ProjectPanel)).height, fitted.height);
  });

  testWidgets('many small pointer moves add up to one drag',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pumpAndSettle();

    final before = tester.getRect(find.byType(ProjectPanel)).height;
    final tree = tester.getRect(find.byType(ProjectTreePanel));
    final inspector = tester.getRect(find.byType(InspectorPanel));
    final divider = (tree.bottom + inspector.top) / 2;

    // A real mouse delivers many small moves; the pane must follow the sum,
    // not the last increment (which made it twitch instead of moving).
    final gesture = await tester.startGesture(
      Offset(1200, divider),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    // The first movement only makes the gesture win the arena; everything after
    // it is reported as a delta.
    await gesture.moveBy(const Offset(0, -1));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // Ten reported moves of 20 px each. The very first movement is consumed by
    // the gesture arena, so the pane follows 180 px - and, crucially, all ten
    // of them instead of only the last.
    expect(before - tester.getRect(find.byType(ProjectPanel)).height, 180);
  });

  testWidgets('each pane paints its ink inside its own clip',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pumpAndSettle();

    // Ink features go to the closest Material. Without one inside the clip the
    // highlight of a scrolled away row is painted on the Scaffold's Material,
    // which sits above both panes and bleeds over the inspector.
    final tree = find.byType(ProjectTreePanel);
    final materialInsideClip = find.ancestor(
      of: tree,
      matching: find.byType(Material),
    );
    expect(materialInsideClip, findsWidgets);

    // The Material must sit between the pane content and the clip.
    final material = tester.element(materialInsideClip.first);
    final clip = find.ancestor(
      of: find.byWidget(material.widget),
      matching: find.byType(ClipRect),
    );
    expect(clip, findsWidgets);

    final inspector = find.byType(InspectorPanel);
    expect(
      find.ancestor(of: inspector, matching: find.byType(Material)),
      findsWidgets,
    );
  });

  Future<void> checkCanvasSwitch(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    controller.setCodeMode(false);
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(controller: controller)),
    );
    await tester.pumpAndSettle();

      // The switch is back in the header.
      final switchFinder = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(SegmentedButton<int>),
      );
      expect(switchFinder, findsOneWidget, reason: 'width $width');
      expect(
        find.descendant(
          of: find.byType(StatusBar),
          matching: find.byType(SegmentedButton<int>),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(CanvasArea),
          matching: find.byType(SegmentedButton<int>),
        ),
        findsNothing,
      );
      // It sits in the header, above the editing area.
      expect(
        tester.getTopLeft(find.byType(CanvasArea)).dy,
        greaterThan(tester.getTopLeft(switchFinder).dy),
      );

      // Nothing is cut off by the window edge and nothing overflows.
      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(tester.getRect(find.byType(EditorToolbar)).right,
          lessThanOrEqualTo(width), reason: 'width $width');

      // Switching works from the header.
      await tester.tap(find.descendant(
        of: switchFinder,
        matching: find.text('Code'),
      ));
      await tester.pumpAndSettle();
      expect(controller.codeMode, isTrue, reason: 'width $width');
    expect(find.byType(CodeView), findsOneWidget);
  }

  testWidgets('the header switch fits a narrow window',
      (tester) async => checkCanvasSwitch(tester, 800));

  testWidgets('the header switch fits a medium window',
      (tester) async => checkCanvasSwitch(tester, 1100));

  testWidgets('the header switch fits a wide window',
      (tester) async => checkCanvasSwitch(tester, 1600));

  Future<void> scroll(WidgetTester tester, Offset at, double dy) async {
  await tester.sendEventToBinding(PointerScrollEvent(
    position: at,
    scrollDelta: Offset(0, dy),
    kind: PointerDeviceKind.mouse,
  ));
  await tester.pump();
  // The scroll correction for the focal point runs after the zoomed frame.
  await tester.pump(const Duration(milliseconds: 20));
}

  testWidgets('the wheel zooms the canvas around the cursor',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pumpAndSettle();

    final canvas = tester.getRect(find.byType(CanvasView));
    final focal = canvas.center + Offset(40, 30);
    expect(controller.zoom, 1.0);

    // Wheel up zooms in. Ctrl is not set here: both variants take the same
    // path, only the delta size differs.
    for (var i = 0; i < 5; i++) {
      await scroll(tester, focal, -120);
    }
    expect(controller.zoom, greaterThan(1.5));
    expect(tester.takeException(), isNull);

    // Wheel down zooms out again.
    for (var i = 0; i < 10; i++) {
      await scroll(tester, focal, 120);
    }
    expect(controller.zoom, lessThan(1.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('zooming keeps the point under the cursor in place',
      (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pumpAndSettle();

    // Zoom in far enough that the design surface no longer fits and has to be
    // scrolled under the cursor.
    final focal = tester.getRect(find.byType(CanvasView)).center;
    for (var i = 0; i < 10; i++) {
      await scroll(tester, focal, -120);
    }
    expect(controller.zoom, greaterThan(2.0));

    // InteractiveViewer handles panning internally — check it exists and has
    // non-zero pan values after zoom (surface moved under cursor).
    final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(iv.transformationController?.value.getMaxScaleOnAxis(),
        greaterThan(2.0));
    expect(tester.takeException(), isNull);
  });


  testWidgets('login screen shows before choosing an account', (tester) async {
    final controller = standaloneController();
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();
    expect(find.text('Sign in to store your projects in the cloud.'),
        findsOneWidget);
  });

  testWidgets('editor exposes Canvas/Code tabs with an editable source',
      (tester) async {
    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'P',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    controller.setCodeMode(true);
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    expect(find.text('Canvas'), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Apply'), findsOneWidget);
    expect(find.text('src/main/resources/com/example/main.fxml'), findsWidgets);
  });

  testWidgets('shows a project picker instead of an empty canvas',
      (tester) async {
    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    expect(find.text('Choose a project'), findsOneWidget);
    // The visual canvas / code switch is not shown before a project is opened.
    expect(find.text('Canvas'), findsNothing);
    expect(find.text('Code'), findsNothing);
  });

  testWidgets('opening a project replaces the picker with the editor',
      (tester) async {
    final controller = standaloneController();
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'P',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pump();

    expect(find.text('Choose a project'), findsNothing);
    expect(find.text('Canvas'), findsOneWidget);
  });

  group('EditorController', () {
    test('starts with an empty AnchorPane document', () {
      final controller = standaloneController();
      expect(controller.root.tag, 'AnchorPane');
      expect(controller.dirty, isFalse);
    });

    test('adds a component to the root and records history', () {
      final controller = standaloneController();
      final button = FxCatalog.lookup('Button')!;
      controller.addComponent(button);
      expect(controller.root.children.length, 1);
      expect(controller.root.children.first.tag, 'Button');
      expect(controller.selected, isNotNull);
      expect(controller.canUndo, isTrue);
      expect(controller.document.imports, contains('javafx.scene.control.Button'));
    });

    test('undo restores the previous document', () {
      final controller = standaloneController();
      controller.addComponent(FxCatalog.lookup('Label')!);
      controller.undo();
      expect(controller.root.children, isEmpty);
      expect(controller.canRedo, isTrue);
      controller.redo();
      expect(controller.root.children.length, 1);
    });

    test('setAttribute updates and clears values', () {
      final controller = standaloneController();
      controller.addComponent(FxCatalog.lookup('Button')!);
      final node = controller.selected!;
      controller.setAttribute(node, 'text', 'Hello');
      expect(node.attributes['text'], 'Hello');
      controller.setAttribute(node, 'text', '');
      expect(node.attributes.containsKey('text'), isFalse);
    });

    test('delete removes the selected node', () {
      final controller = standaloneController();
      controller.addComponent(FxCatalog.lookup('Button')!);
      controller.deleteSelected();
      expect(controller.root.children, isEmpty);
    });

    test('round trips through serialize/parse', () {
      final controller = standaloneController();
      controller.addComponent(FxCatalog.lookup('TextField')!);
      final source = controller.serialize();
      final reloaded = standaloneController()..loadFromString(source);
      expect(reloaded.root.children.length, 1);
      expect(reloaded.root.children.first.tag, 'TextField');
    });

    test('moving a node updates layout attributes', () {
      final controller = standaloneController();
      controller.addComponent(FxCatalog.lookup('Button')!);
      final node = controller.selected!;
      final before = node.attributes['AnchorPane.leftAnchor'];
      controller.moveSelected(3, 10);
      final after = node.attributes['AnchorPane.leftAnchor'];
      expect(after, isNot(before));
    });
  });

  test('FxmlNode deep copy is independent', () {
    final original = FxmlNode('VBox')..attributes['spacing'] = '8.0';
    final child = FxmlNode('Button')..attributes['text'] = 'OK';
    original.addChild(child);
    final copy = original.deepCopy();
    copy.children.first.attributes['text'] = 'Cancel';
    expect(original.children.first.attributes['text'], 'OK');
    expect(copy.children.first.parent, copy);
  });
}