import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Modal dialog for creating a new folder.
Future<String?> showNewFolderModal(BuildContext context) {
  final nameController = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(context.tr('New folder')),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.tr('Folder name'),
                  hintText: 'utils',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
            child: Text(context.tr('Create')),
          ),
        ],
      );
    },
  );
}
