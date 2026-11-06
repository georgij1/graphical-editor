import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Тип создаваемого файла.
enum NewFileType {
  java('Java', '.java', Icons.data_object),
  fxml('FXML', '.fxml', Icons.code),
  xml('XML', '.xml', Icons.code),
  txt('Text', '.txt', Icons.text_fields),
  md('Markdown', '.md', Icons.article),
  properties('Properties', '.properties', Icons.settings);

  const NewFileType(this.label, this.extension, this.icon);

  final String label;
  final String extension;
  final IconData icon;
}

/// Диалог создания нового файла с выбором типа.
Future<Map<String, String>?> showNewFileModal(BuildContext context) async {
  final nameController = TextEditingController();
  NewFileType selectedType = NewFileType.java;

  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(context.tr('New file')),
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
                      labelText: context.tr('File name'),
                      hintText: 'example',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixText: selectedType.extension,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Text(context.tr('File type'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: NewFileType.values.map((type) {
                      final isSelected = type == selectedType;
                      return FilterChip(
                        label: Text(type.label),
                        selected: isSelected,
                        onSelected: (_) => setState(() => selectedType = type),
                        avatar: Icon(type.icon, size: 18),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
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
                  final fullName = name.endsWith(selectedType.extension)
                      ? name
                      : '$name${selectedType.extension}';
                  Navigator.of(context).pop({
                    'name': fullName,
                    'type': selectedType.label,
                    'extension': selectedType.extension,
                  });
                },
                child: Text(context.tr('Create')),
              ),
            ],
          );
        },
      );
    },
  );
}
