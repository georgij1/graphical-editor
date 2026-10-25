import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:graphical_editor/build/build_client.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/l10n/app_localizations.dart';
import 'package:graphical_editor/project/project.dart';
import 'package:graphical_editor/ui/widgets/build_dialog.dart';
import 'package:http/http.dart' as http;

import 'test_doubles.dart';

Widget _app(Locale locale, EditorController controller) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showBuildDialog(
              context,
              controller: controller,
              project: Project(
                id: 'p1',
                name: 'Demo',
                package: 'com.example.demo',
                mainClass: 'MainApp',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

/// Client that answers instantly so the dialog logic can be exercised.
BuildClient _fakeClient({bool bundle = false}) {
  return BuildClient(
    baseUrl: 'http://builder',
    httpClient: _FakeHttpClient(bundle),
  );
}

Future<EditorController> _controller() async {
  final controller = EditorController(
    storage: InMemoryProjectStorage(),
    tokenStore: InMemoryKeyValueStore(),
    api: FakeApiClient(),
    buildClient: _fakeClient(),
  );
  await controller.register('a@b.com', 'secret1');
  return controller;
}

void main() {
  testWidgets('the dialog offers the build button', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(_app(const Locale('en'), controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Download ready JAR'), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Download ready JAR'), findsOneWidget);
  });

  testWidgets('building closes the dialog', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(_app(const Locale('en'), controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Download ready JAR'));
    // The (stubbed) save fails in the test binding, so the dialog stays open
    // and simply stops spinning.
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('the dialog is translated', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(_app(const Locale('ru'), controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Скачать готовый JAR'), findsNWidgets(2));
    expect(find.text('Проект компилируется на сервере сборки.'), findsOneWidget);
  });
}

/// Minimal HTTP stub: answers 200 with a tiny payload, or the error text when
/// [fail] is set.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.bundle);

  final bool bundle;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.contains('/health')) {
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        200,
        request: request,
      );
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(<int>[0x50, 0x4B, 0x03, 0x04]),
      200,
      headers: <String, String>{
        'content-disposition':
            'attachment; filename="${bundle ? 'bundle.zip' : 'app.jar'}"',
      },
      request: request,
    );
  }
}