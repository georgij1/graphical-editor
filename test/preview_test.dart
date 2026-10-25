import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/editor/fx_catalog.dart';
import 'package:graphical_editor/io/file_service.dart';
import 'package:graphical_editor/model/fxml_node.dart';
import 'package:graphical_editor/preview/html_preview.dart';
import 'package:graphical_editor/preview/html_surface_stub.dart';
import 'package:graphical_editor/preview/preview_view.dart';
import 'package:graphical_editor/ui/editor_page.dart';
import 'package:graphical_editor/ui/widgets/inspector_panel.dart';
import 'package:graphical_editor/ui/widgets/status_bar.dart';
import 'package:graphical_editor/ui/widgets/user_avatar.dart';

import 'test_doubles.dart';

FxmlNode node(
  String tag, {
  Map<String, String> attributes = const <String, String>{},
  List<FxmlNode> children = const <FxmlNode>[],
}) {
  final FxmlNode result = FxmlNode(tag);
  result.attributes.addAll(attributes);
  for (final child in children) {
    result.children.add(child);
  }
  return result;
}

FxmlDocument documentOf(FxmlNode root) => FxmlDocument(root: root);

/// Relative luminance difference between two opaque colours.
double _contrast(Color a, Color b) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

  double luminance(Color color) => 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);

  return (luminance(a) - luminance(b)).abs();
}
void main() {
  group('browser preview', () {
    test('produces a standalone document', () {
      final String html = buildPreviewHtml(
        documentOf(node('VBox', children: <FxmlNode>[
          node('Label', attributes: <String, String>{'text': 'Hello'}),
        ])),
      );

      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('</html>'));
      expect(html, contains('Hello'));
    });

    test('reproduces the layout of the common containers', () {
      final String html = buildPreviewHtml(documentOf(node('VBox', attributes: <String, String>{
        'spacing': '10',
      }, children: <FxmlNode>[
        node('Label', attributes: <String, String>{'text': 'One'}),
        node('Button', attributes: <String, String>{'text': 'Two'}),
      ])));

      expect(html, contains('flex-direction:column'));
      expect(html, contains('gap:10px'));
      expect(html, contains('<button'));
      expect(html, contains('Two'));
    });

    test('turns anchored children into absolute placement', () {
      final String html = buildPreviewHtml(documentOf(node('AnchorPane', children: <FxmlNode>[
        node('Button', attributes: <String, String>{
          'text': 'OK',
          'AnchorPane.topAnchor': '24',
          'AnchorPane.leftAnchor': '16',
        }),
      ])));

      expect(html, contains('position:absolute'));
      expect(html, contains('top:24px'));
      expect(html, contains('left:16px'));
    });

    test('places grid children in their cells', () {
      final String html = buildPreviewHtml(documentOf(node('GridPane', attributes: <String, String>{
        'hgap': '6',
        'vgap': '8',
      }, children: <FxmlNode>[
        node('Label', attributes: <String, String>{
          'text': 'A',
          'GridPane.rowIndex': '1',
          'GridPane.columnIndex': '2',
        }),
      ])));

      expect(html, contains('grid-column:3 / span 1'));
      expect(html, contains('grid-row:2 / span 1'));
      expect(html, contains('column-gap:6px'));
    });

    test('reports the Java handler a control would call', () {
      final String html = buildPreviewHtml(documentOf(node('VBox', children: <FxmlNode>[
        node('Button', attributes: <String, String>{
          'fx:id': 'okButton',
          'text': 'OK',
          'onAction': '#handleOk',
        }),
      ])));

      expect(html, contains('data-handler="handleOk"'));
      expect(html, contains('data-fx-id="okButton"'));
    });

    test('keeps the selected state of checkboxes and toggle buttons', () {
      final String html = buildPreviewHtml(documentOf(node('VBox', children: <FxmlNode>[
        node('CheckBox', attributes: <String, String>{
          'text': 'On',
          'selected': 'true',
        }),
        node('ToggleButton', attributes: <String, String>{'text': 'T'}),
      ])));

      expect(html, contains('type="checkbox" checked'));
      expect(html, contains('data-toggle="true"'));
      expect(html, contains('aria-pressed="false"'));
    });

    test('lists the items of a combo box and a list view', () {
      final items = node('items', children: <FxmlNode>[
        node('String', attributes: <String, String>{'fx:value': 'One'}),
        node('String', attributes: <String, String>{'fx:value': 'Two'}),
      ]);
      final String html = buildPreviewHtml(documentOf(node('VBox', children: <FxmlNode>[
        node('ComboBox', children: <FxmlNode>[items]),
      ])));

      expect(html, contains('<select'));
      expect(html, contains('<option>One</option>'));
      expect(html, contains('<option>Two</option>'));
    });

    test('converts JavaFX style declarations into CSS', () {
      final String html = buildPreviewHtml(documentOf(node('VBox', children: <FxmlNode>[
        node('Label', attributes: <String, String>{
          'text': 'Styled',
          'style': '-fx-background-color: LIGHTBLUE; -fx-text-fill: WHITE;',
        }),
      ])));

      expect(html, contains('background:#add8e6'));
      expect(html, contains('color:#ffffff'));
    });

    test('honours sizing and visibility', () {
      final String html = buildPreviewHtml(documentOf(node('VBox', children: <FxmlNode>[
        node('Button', attributes: <String, String>{
          'text': 'Wide',
          'prefWidth': '240',
          'disable': 'true',
        }),
        node('Label', attributes: <String, String>{
          'text': 'Hidden',
          'visible': 'false',
        }),
      ])));

      expect(html, contains('width:240px'));
      expect(html, contains('disabled'));
      expect(html, contains('visibility:hidden'));
    });

    test('escapes text so the page cannot break out of an attribute', () {
      final String html = buildPreviewHtml(documentOf(node('VBox', children: <FxmlNode>[
        node('Label', attributes: <String, String>{'text': '<script>"x"</script>'}),
      ])));

      expect(html, isNot(contains('<script>"x"')));
      expect(html, contains('&lt;script&gt;'));
    });
  });

  testWidgets('the preview fills the window and can be closed',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: InMemoryKeyValueStore(),
      api: FakeApiClient(),
    );
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pumpAndSettle();

    // The run button lives in the status bar, next to the node count, and not
    // in the crowded header.
    final runButton = find.widgetWithText(TextButton, 'Run preview');
    expect(runButton, findsOneWidget);
    expect(
      find.descendant(of: find.byType(StatusBar), matching: runButton),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: runButton),
      findsNothing,
    );
    expect(tester.getTopLeft(runButton).dy,
        greaterThan(tester.getBottomLeft(find.byType(StatusBar)).dy - 28));

    showPreview(tester.element(find.byType(EditorPage)), controller);
    await tester.pumpAndSettle();

    // A full screen route, not a dialog: the preview body reaches the window
    // edges and sits directly under its own header.
    expect(find.byType(PreviewPage), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    final surface = tester.getRect(find.byType(HtmlSurfacePlaceholder));
    expect(surface.left, lessThan(20));
    expect(surface.right, greaterThan(1260));
    expect(surface.height, greaterThan(600));

    // Closing returns to the editor.
    await tester.tap(find.byTooltip('Close preview'));
    await tester.pumpAndSettle();
    expect(find.byType(PreviewPage), findsNothing);
    expect(find.byType(EditorPage), findsOneWidget);
  });

  testWidgets('saving writes to the workspace and downloads nothing',
      (tester) async {
    final saved = <String>[];
    final storage = InMemoryProjectStorage();
    final controller = EditorController(
      fileService: _RecordingFileService(saved),
      storage: storage,
      tokenStore: InMemoryKeyValueStore(),
      api: FakeApiClient(),
    );
    await controller.register('a@b.com', 'secret1');
    expect(
      controller.loadFromString(
        '<AnchorPane xmlns:fx="http://javafx.com/fxml">'
        '<Button fx:id="ok" text="OK" />'
        '</AnchorPane>',
        fileName: 'untitled',
      ),
      isTrue,
    );
    expect(controller.dirty, isFalse);

    controller.newDocument();
    controller.loadFromString(
      '<AnchorPane xmlns:fx="http://javafx.com/fxml">'
      '<Label fx:id="hello" text="Hello" />'
      '</AnchorPane>',
      fileName: 'untitled',
    );
    expect(controller.dirty, isFalse);

    final ok = await controller.saveDocument();
    expect(ok, isTrue);
    expect(saved, isEmpty, reason: 'saving must not write a file');

    // The document survives a reload of the workspace.
    await controller.flushAutosave;
    final reopened = EditorController(
      fileService: _RecordingFileService(saved),
      storage: storage,
      tokenStore: InMemoryKeyValueStore(),
      api: FakeApiClient(),
    );
    await reopened.register('a@b.com', 'secret1');
    await reopened.loadWorkspace();
    await tester.pump();

    expect(reopened.hasOpenDocument, isTrue);
    expect(reopened.serialize(), contains('Hello'));
    expect(saved, isEmpty);
  });

  testWidgets('the account button sits at the right of the editor header',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: InMemoryKeyValueStore(),
      api: FakeApiClient(),
    );
    await controller.register('a@b.com', 'secret1');
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pumpAndSettle();

    final account = find.descendant(
      of: find.byType(AppBar),
      matching: find.byTooltip('Account'),
    );
    expect(account, findsOneWidget);
    // Without a project the header holds nothing else, so it is the only
    // action and sits at the far right already.
    expect(tester.getTopRight(account).dx, greaterThan(1500));

    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpAndSettle();

    // Settings is reachable from the account menu, not from the header.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.settings_outlined),
      ),
      findsNothing,
    );
    await tester.tap(account);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();

    final grid = find.widgetWithIcon(IconButton, Icons.grid_4x4);
    expect(grid, findsOneWidget);
    expect(
      tester.getTopLeft(account).dx,
      greaterThan(tester.getTopLeft(grid).dx),
      reason: 'the account button must be the rightmost header action',
    );
    // Right-aligned: it ends close to the window edge.
    expect(tester.getTopRight(account).dx, greaterThan(1500));

    // The login is shown next to the avatar.
    expect(
      find.descendant(of: account, matching: find.text('a@b.com')),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.text('a@b.com')).dx,
      lessThan(tester.getCenter(find.byType(UserAvatar)).dx),
    );
  });

  testWidgets('the project name stays visible in a crowded header',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: InMemoryKeyValueStore(),
      api: FakeApiClient(),
    );
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'MyVeryLongProjectName',
      package: 'com.example.myapp',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pumpAndSettle();

    // The header shows "Project/scene.fxml"; the project name leads it.
    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data ?? '').startsWith('MyVeryLongProjectName'),
      ),
    );
    expect(title, findsOneWidget);
    // It must not be squeezed to a sliver by the toolbar and the account
    // button, which share the header with it.
    expect(tester.getSize(title).width, greaterThan(60));
    expect(
      tester.getTopLeft(title).dx + tester.getSize(title).width,
      lessThan(tester.getTopLeft(find.byType(SegmentedButton<int>)).dx),
    );
  });

  testWidgets('the project name is readable on the dark theme',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: InMemoryKeyValueStore(),
      api: FakeApiClient(),
    );
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'MyApp',
      package: 'com.example.myapp',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: EditorPage(controller: controller),
    ));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.descendant(
      of: find.byType(AppBar),
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data ?? '').startsWith('MyApp'),
      ),
    ));
    final background = Theme.of(tester.element(find.byType(AppBar)))
        .appBarTheme
        .backgroundColor ??
        Theme.of(tester.element(find.byType(AppBar))).colorScheme.surface;

    expect(title.style?.color, isNotNull,
        reason: 'the title must not rely on an inherited colour');
    expect(
      _contrast(title.style!.color!, background),
      greaterThan(0.5),
      reason: 'the project name must stand out from the header',
    );
  });

  testWidgets('Backspace in an inspector field does not delete the node',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: InMemoryKeyValueStore(),
      api: FakeApiClient(),
    );
    await controller.register('a@b.com', 'secret1');
    controller.createProject(
      name: 'Demo',
      package: 'com.example',
      mainClass: 'MainApp',
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.pumpAndSettle();

    final button = FxCatalog.components.firstWhere((entry) => entry.name == 'Button');
    controller.addComponent(button);
    await tester.pumpAndSettle();
    expect(controller.nodeCount, greaterThan(1));

    // Select the button and edit its text through the inspector.
    FxmlNode buttonNode() =>
        controller.root.children.firstWhere((node) => node.tag == 'Button');
    controller.select(buttonNode());
    await tester.pumpAndSettle();

    final field = find.descendant(
      of: find.byType(InspectorPanel),
      matching: find.byType(EditableText),
    );
    expect(field, findsWidgets);
    final editable = tester.widget<EditableText>(field.first);
    await tester.enterText(field.first, 'Captio');
    await tester.pumpAndSettle();

    // Backspace must erase a character in the field...
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(editable.controller.text, 'Capti');

    // ...and must not remove the button from the canvas.
    expect(controller.nodeCount, greaterThan(1),
        reason: 'the node was deleted while its text was edited');
    expect(buttonNode().tag, 'Button');
  });
}

/// Fails loudly if anything but [EditorController.saveFile] tries to write.
class _RecordingFileService extends FileService {
  _RecordingFileService(this.saved);

  final List<String> saved;

  @override
  Future<bool> save(
    String content,
    String fileName, {
    String? dialogTitle,
    List<String> allowedExtensions = const <String>['fxml'],
    String? mimeType,
  }) async {
    saved.add(fileName);
    return true;
  }
}
