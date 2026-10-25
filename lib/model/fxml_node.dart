/// A single element of an FXML document (a JavaFX node, a property element or a
/// value object such as `Font`/`Insets`).
///
/// The model keeps enough information to round-trip a document losslessly while
/// still exposing a convenient tree for the editor UI.
class FxmlNode {
  FxmlNode(this.tag, {this.isProperty = false});

  /// Element name as written in the document, e.g. `VBox`, `Button`, `padding`.
  final String tag;

  /// Property elements (lower-case tags such as `padding`, `font`, `top`) are
  /// serialized without a `<children>` wrapper.
  final bool isProperty;

  /// Simple attributes, keyed by their qualified name (e.g. `fx:id`).
  final Map<String, String> attributes = <String, String>{};

  /// Component children, in document order.
  final List<FxmlNode> children = <FxmlNode>[];

  /// Property elements keyed by tag (`font`, `padding`, `top`, ...).
  final Map<String, FxmlNode> properties = <String, FxmlNode>{};

  /// Text content of the element, if any.
  String? text;

  /// Whether the children were wrapped in an explicit `<children>` element.
  bool explicitChildrenTag = false;

  /// Back-reference used for tree navigation. Maintained by [addChild]/[remove].
  FxmlNode? parent;

  /// Creates an independent copy of this node (including the whole subtree).
  FxmlNode deepCopy({FxmlNode? newParent}) {
    final copy = FxmlNode(tag, isProperty: isProperty)
      ..text = text
      ..explicitChildrenTag = explicitChildrenTag
      ..parent = newParent;
    copy.attributes.addAll(attributes);
    for (final entry in properties.entries) {
      copy.properties[entry.key] = entry.value.deepCopy(newParent: copy);
    }
    for (final child in children) {
      copy.children.add(child.deepCopy(newParent: copy));
    }
    return copy;
  }

  /// Appends [child] to this node and wires the back-reference.
  void addChild(FxmlNode child, {int? at}) {
    child.parent = this;
    if (at == null || at < 0 || at > children.length) {
      children.add(child);
    } else {
      children.insert(at, child);
    }
  }

  /// Removes [child] from this node if present.
  bool removeChild(FxmlNode child) {
    final removed = children.remove(child);
    if (removed) child.parent = null;
    return removed;
  }

  /// Depth-first iterator over this node and all descendants.
  Iterable<FxmlNode> get descendantsAndSelf sync* {
    yield this;
    for (final child in children) {
      yield* child.descendantsAndSelf;
    }
    for (final property in properties.values) {
      yield* property.descendantsAndSelf;
    }
  }

  /// Only component descendants (children tree), excluding property values.
  Iterable<FxmlNode> get componentDescendants sync* {
    for (final child in children) {
      yield child;
      yield* child.componentDescendants;
    }
  }

  String? get fxId => attributes['fx:id'];

  String get displayName => fxId == null ? tag : '$tag ($fxId)';

  @override
  String toString() => 'FxmlNode($tag, attrs: ${attributes.length}, '
      'children: ${children.length})';
}

/// A parsed `.fxml` document.
class FxmlDocument {
  FxmlDocument({
    required this.root,
    List<String>? imports,
  }) : imports = imports ?? <String>[];

  FxmlNode root;

  /// `<?import ...?>` statements, without the surrounding processing markers.
  List<String> imports;

  /// Deep copy of the whole document.
  FxmlDocument deepCopy() =>
      FxmlDocument(root: root.deepCopy(), imports: List<String>.from(imports));

  /// All nodes reachable from the root.
  Iterable<FxmlNode> get allNodes => root.descendantsAndSelf;

  /// A reasonable default document used when the editor starts empty.
  static FxmlDocument empty() {
    final root = FxmlNode('AnchorPane')
      ..attributes.addAll(<String, String>{
        'xmlns': 'http://javafx.com/javafx/17.0.2',
        'xmlns:fx': 'http://javafx.com/fxml/1',
        'prefWidth': '800.0',
        'prefHeight': '600.0',
      });
    return FxmlDocument(
      root: root,
      imports: <String>[
        'javafx.scene.layout.*',
        'javafx.scene.control.*',
      ],
    );
  }
}
