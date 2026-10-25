import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/editor_controller.dart';
import '../../editor/fx_meta.dart';
import '../../model/fxml_node.dart';
import 'color_picker_dialog.dart';
import '../../l10n/app_localizations.dart';

/// Property inspector for the currently selected node.
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final node = controller.selected;
    if (node == null) {
      return const _EmptyInspector();
    }
    final parentTag = node.parent?.tag;
    final props = FxMeta.propsFor(node.tag, parentTag: parentTag);
    final groups = <String, List<FxProp>>{};
    for (final prop in props) {
      groups.putIfAbsent(prop.group, () => <FxProp>[]).add(prop);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _Header(controller: controller, node: node),
        const Divider(height: 1),
        for (final entry in groups.entries)
          _PropSection(
            title: entry.key,
            controller: controller,
            node: node,
            props: entry.value,
            parentTag: parentTag,
          ),
        _FontSection(controller: controller, node: node),
        _PaddingSection(controller: controller, node: node),
        _RawAttributesSection(controller: controller, node: node),
      ],
    );
  }
}

class _EmptyInspector extends StatelessWidget {
  const _EmptyInspector();

@override
  Widget build(BuildContext context) {
    // The pane can be squeezed to a few dozen pixels by the split handle, so
    // the hint scrolls instead of overflowing past the divider.
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.tune,
                  size: 40, color: Theme.of(context).disabledColor),
              const SizedBox(height: 12),
              Text(
                context.tr('Select an element on the canvas to edit its properties.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.node});

  final EditorController controller;
  final FxmlNode node;

  @override
  Widget build(BuildContext context) {
    final canReorder = node.parent != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  node.tag,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  node.fxId != null ? 'fx:id="${node.fxId}"' : context.tr('no fx:id'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('Move up'),
            iconSize: 18,
            onPressed:
                canReorder ? () => controller.reorderSelected(-1) : null,
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            tooltip: context.tr('Move down'),
            iconSize: 18,
            onPressed:
                canReorder ? () => controller.reorderSelected(1) : null,
            icon: const Icon(Icons.arrow_downward),
          ),
          IconButton(
            tooltip: context.tr('Duplicate'),
            iconSize: 18,
            onPressed:
                canReorder ? controller.duplicateSelected : null,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: context.tr('Delete'),
            iconSize: 18,
            onPressed: controller.deleteSelected,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _PropSection extends StatelessWidget {
  const _PropSection({
    required this.title,
    required this.controller,
    required this.node,
    required this.props,
    required this.parentTag,
  });

  final String title;
  final EditorController controller;
  final FxmlNode node;
  final List<FxProp> props;
  final String? parentTag;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(
        context.tr(title),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: <Widget>[
        for (final prop in props)
          _PropertyRow(controller: controller, node: node, prop: prop),
      ],
    );
  }
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({
    required this.controller,
    required this.node,
    required this.prop,
  });

  final EditorController controller;
  final FxmlNode node;
  final FxProp prop;

  @override
  Widget build(BuildContext context) {
    if (prop.kind == FxPropKind.insets) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(prop.label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            _InsetsEditor(
              controller: controller,
              owner: node,
              propertyTag: prop.name,
              valueTag: 'Insets',
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 108,
            child: Text(
              prop.label,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: _editor(context)),
        ],
      ),
    );
  }

  Widget _editor(BuildContext context) {
    final value = node.attributes[prop.name] ?? '';
    switch (prop.kind) {
      case FxPropKind.number:
        return _SyncedTextField(
          value: value,
          hint: '—',
          numeric: true,
          onChanged: (v) => controller.setAttribute(node, prop.name, v),
        );
      case FxPropKind.boolean:
        return _EnumDropdown(
          value: value.isEmpty ? '' : value,
          values: prop.values,
          onChanged: (v) => controller.setAttribute(node, prop.name, v),
        );
      case FxPropKind.enumeration:
        return _EnumDropdown(
          value: value,
          values: prop.values,
          onChanged: (v) => controller.setAttribute(node, prop.name, v),
        );
      case FxPropKind.color:
        return _ColorField(
          controller: controller,
          node: node,
          name: prop.name,
          value: value,
        );
      case FxPropKind.multiline:
        return _SyncedTextField(
          value: value,
          hint: '—',
          maxLines: 3,
          onChanged: (v) => controller.setAttribute(node, prop.name, v),
        );
      case FxPropKind.text:
      case FxPropKind.insets:
        return _SyncedTextField(
          value: value,
          hint: '—',
          onChanged: (v) => controller.setAttribute(node, prop.name, v),
        );
    }
  }
}

class _EnumDropdown extends StatelessWidget {
  const _EnumDropdown({
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(value: '', child: Text('—')),
      for (final v in values)
        DropdownMenuItem<String>(value: v, child: Text(v)),
    ];
    return DropdownButtonFormField<String>(
      initialValue: value.isEmpty || !values.contains(value) ? '' : value,
      isDense: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      items: items,
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

class _ColorField extends StatelessWidget {
  const _ColorField({
    required this.controller,
    required this.node,
    required this.name,
    required this.value,
  });

  final EditorController controller;
  final FxmlNode node;
  final String name;
  final String value;

  Color _preview() {
    var text = value.trim();
    if (text.startsWith('#')) text = text.substring(1);
    if (text.length == 3) {
      text = text.split('').map((c) => '$c$c').join();
    }
    if (text.length >= 6) {
      final parsed = int.tryParse(text.substring(0, 6), radix: 16);
      if (parsed != null) return Color(0xFF000000 | parsed);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _SyncedTextField(
            value: value,
            hint: '—',
            onChanged: (v) => controller.setAttribute(node, name, v),
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: () async {
            final picked =
                await showFxColorPicker(context, initial: value);
            if (picked != null) controller.setAttribute(node, name, picked);
          },
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _preview(),
              border: Border.all(color: const Color(0xFF999999)),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}

class _FontSection extends StatelessWidget {
  const _FontSection({required this.controller, required this.node});

  final EditorController controller;
  final FxmlNode node;

  String _fontAttr(String name) {
    final font = node.properties['font'];
    if (font == null || font.children.isEmpty) return '';
    return font.children.first.attributes[name] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
title: Text(context.tr('Font'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: <Widget>[
Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 108,
                child: Text(context.tr('size'),
                    style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _SyncedTextField(
                  value: _fontAttr('size'),
                  hint: '—',
                  numeric: true,
                  onChanged: (v) =>
                      controller.setPropertyAttribute(node, 'font', 'Font', 'size', v),
                ),
              ),
            ],
          ),
        ),
Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 108,
                child: Text(context.tr('family'),
                    style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _SyncedTextField(
                  value: _fontAttr('name'),
                  hint: '—',
                  onChanged: (v) =>
                      controller.setPropertyAttribute(node, 'font', 'Font', 'name', v),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaddingSection extends StatelessWidget {
  const _PaddingSection({required this.controller, required this.node});

  final EditorController controller;
  final FxmlNode node;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
title: Text(context.tr('Padding'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: <Widget>[
        _InsetsEditor(
          controller: controller,
          owner: node,
          propertyTag: 'padding',
          valueTag: 'Insets',
        ),
      ],
    );
  }
}

class _InsetsEditor extends StatelessWidget {
  const _InsetsEditor({
    required this.controller,
    required this.owner,
    required this.propertyTag,
    required this.valueTag,
  });

  final EditorController controller;
  final FxmlNode owner;
  final String propertyTag;
  final String valueTag;

  String _value(String side) {
    final property = owner.properties[propertyTag];
    if (property == null || property.children.isEmpty) return '';
    return property.children.first.attributes[side] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    const sides = <String>['top', 'right', 'bottom', 'left'];
    return Row(
      children: <Widget>[
        for (final side in sides)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                children: <Widget>[
                  Text(side, style: const TextStyle(fontSize: 10)),
                  _SyncedTextField(
                    value: _value(side),
                    hint: '0',
                    numeric: true,
                    onChanged: (v) => controller.setPropertyAttribute(
                        owner, propertyTag, valueTag, side, v),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RawAttributesSection extends StatelessWidget {
  const _RawAttributesSection({required this.controller, required this.node});

  final EditorController controller;
  final FxmlNode node;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
title: Text(context.tr('All attributes'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: <Widget>[
        for (final entry in node.attributes.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 108,
                  child: Text(
                    entry.key,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SyncedTextField(
                    value: entry.value,
                    hint: '—',
                    onChanged: (v) =>
                        controller.setAttribute(node, entry.key, v),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Remove'),
                  iconSize: 16,
                  onPressed: () =>
                      controller.removeAttribute(node, entry.key),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        _AddAttributeField(controller: controller, node: node),
      ],
    );
  }
}

class _AddAttributeField extends StatefulWidget {
  const _AddAttributeField({required this.controller, required this.node});

  final EditorController controller;
  final FxmlNode node;

  @override
  State<_AddAttributeField> createState() => _AddAttributeFieldState();
}

class _AddAttributeFieldState extends State<_AddAttributeField> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _value = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

@override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: context.tr('name'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: TextField(
              controller: _value,
              decoration: InputDecoration(
                labelText: context.tr('value'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.tr('Add attribute'),
            onPressed: () {
              final name = _name.text.trim();
              if (name.isEmpty) return;
              widget.controller.setAttribute(widget.node, name, _value.text);
              _name.clear();
              _value.clear();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

/// Text field whose content follows an external value while preserving focus.
class _SyncedTextField extends StatefulWidget {
  const _SyncedTextField({
    required this.value,
    required this.onChanged,
    this.hint,
    this.numeric = false,
    this.maxLines = 1,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final bool numeric;
  final int maxLines;

  @override
  State<_SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<_SyncedTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: widget.maxLines,
      keyboardType: widget.numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      inputFormatters: widget.numeric
          ? <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
            ]
          : null,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      onChanged: widget.onChanged,
    );
  }
}
