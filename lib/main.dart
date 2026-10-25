import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'editor/editor_controller.dart';
import 'l10n/app_localizations.dart';
import 'ui/editor_page.dart';

void main() {
  runApp(const FxmlEditorApp());
}

class FxmlEditorApp extends StatefulWidget {
  const FxmlEditorApp({super.key});

  @override
  State<FxmlEditorApp> createState() => _FxmlEditorAppState();
}

class _FxmlEditorAppState extends State<FxmlEditorApp> {
  /// Owned by the root so the language picker (inside the page) can change
  /// [MaterialApp.locale] by notifying the same controller.
  final EditorController _controller = EditorController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'JavaFX FXML Editor',
          debugShowCheckedModeBanner: false,
          locale: _controller.locale,
          themeMode: switch (_controller.themeSetting) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF039ED3),
              brightness: Brightness.light,
            ),
            visualDensity: VisualDensity.compact,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF039ED3),
              brightness: Brightness.dark,
            ),
            visualDensity: VisualDensity.compact,
          ),
          home: EditorPage(controller: _controller),
        );
      },
    );
  }
}
