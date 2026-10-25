import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../editor/fx_catalog.dart';
import '../../l10n/app_localizations.dart';

/// Palette listing the JavaFX components that can be added to the document.
class PalettePanel extends StatefulWidget {
  const PalettePanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<PalettePanel> createState() => _PalettePanelState();
}

class _PalettePanelState extends State<PalettePanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final categories = FxCategory.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: context.tr('Search components'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: <Widget>[
              for (final category in categories)
                ..._buildCategory(context, category, query),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCategory(
    BuildContext context,
    FxCategory category,
    String query,
  ) {
    final components = FxCatalog.byCategory(category).where((component) {
      if (query.isEmpty) return true;
      return component.name.toLowerCase().contains(query);
    }).toList();
    if (components.isEmpty) return const <Widget>[];
    return <Widget>[
      ExpansionTile(
        initiallyExpanded: query.isNotEmpty || category == FxCategory.controls,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: EdgeInsets.zero,
        title: Text(
          context.tr(category.label),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        children: <Widget>[
          for (final component in components)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(component.icon, size: 18),
              title: Text(component.name, style: const TextStyle(fontSize: 13)),
              onTap: () => widget.controller.addComponent(component),
            ),
        ],
      ),
    ];
  }
}
