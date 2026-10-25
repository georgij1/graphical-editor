import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Dialog that collects the fields needed to create a new JavaFX project.
Future<Map<String, String>?> showNewProjectDialog(BuildContext context) async {
  final name = TextEditingController(text: 'MyApp');
  final package = TextEditingController(text: 'com.example.myapp');
  final mainClass = TextEditingController(text: 'MainApp');
  final description = TextEditingController();

  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(context.tr('New JavaFX project')),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: context.tr('Project name'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: package,
                  decoration: InputDecoration(
                    labelText: context.tr('Java package'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: mainClass,
                  decoration: InputDecoration(
                    labelText: context.tr('Main class'),
                    hintText: 'MainApp',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: description,
                  decoration: InputDecoration(
                    labelText: context.tr('Description (optional)'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(<String, String>{
                'name': name.text,
                'package': package.text,
                'mainClass': mainClass.text,
                'description': description.text,
              });
            },
            child: Text(context.tr('Create')),
          ),
        ],
      );
    },
  );
  name.dispose();
  package.dispose();
  mainClass.dispose();
  description.dispose();
  return result;
}

/// Simple single-field prompt used for renaming projects and scenes.
Future<String?> showPromptDialog(
  BuildContext context, {
  required String title,
  required String initial,
}) {
  final textController = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (value) =>
              Navigator.of(context).pop(textController.text),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(textController.text),
            child: Text(context.tr('OK')),
          ),
        ],
      );
    },
  ).whenComplete(textController.dispose);
}

/// Yes/no confirmation dialog. Returns false when dismissed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.tr('Delete')),
        ),
      ],
    ),
  );
  return result ?? false;
}
