import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../editor/fx_catalog.dart';
import '../../model/fxml_node.dart';

/// Tree view of the document structure.
class OutlinePanel extends StatefulWidget {
  const OutlinePanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  final Set<FxmlNode> _collapsed = <FxmlNode>{};

  @override
  Widget build(BuildContext context) {
    final root = widget.controller.root;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: _buildNode(context, root, 0),
    );
  }

  List<Widget> _buildNode(BuildContext context, FxmlNode node, int depth) {
    final entries = _entries(node);
    final collapsed = _collapsed.contains(node);
    final selected = identical(node, widget.controller.selected);
    final theme = Theme.of(context);
    final icon = FxCatalog.lookup(node.tag)?.icon ?? Icons.widgets_outlined;

    final widgets = <Widget>[
      InkWell(
        onTap: () => widget.controller.select(node),
        child: Container(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.14)
              : null,
          padding: EdgeInsets.only(
            left: 6 + depth * 14.0,
            right: 8,
            top: 5,
            bottom: 5,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 18,
                child: entries.isEmpty
                    ? null
                    : InkWell(
                        onTap: () => setState(() {
                          if (collapsed) {
                            _collapsed.remove(node);
                          } else {
                            _collapsed.add(node);
                          }
                        }),
                        child: Icon(
                          collapsed
                              ? Icons.chevron_right
                              : Icons.expand_more,
                          size: 18,
                        ),
                      ),
              ),
              Icon(icon, size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  node.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    ];

    if (!collapsed) {
      for (final entry in entries) {
        widgets.addAll(_buildNode(context, entry.node, depth + 1));
      }
    }
    return widgets;
  }

  List<_Entry> _entries(FxmlNode node) {
    final result = <_Entry>[
      for (final child in node.children) _Entry('', child),
    ];
    for (final property in node.properties.entries) {
      for (final child in property.value.children) {
        final isComponent = child.tag.isNotEmpty &&
            child.tag[0] == child.tag[0].toUpperCase();
        if (isComponent) {
          result.add(_Entry('${property.key} / ', child));
        }
      }
    }
    return result;
  }
}

class _Entry {
  _Entry(this.prefix, this.node);
  final String prefix;
  final FxmlNode node;
}
