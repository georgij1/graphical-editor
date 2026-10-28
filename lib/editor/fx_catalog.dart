import 'package:flutter/material.dart';

/// Logical grouping used by the component palette.
enum FxCategory {
  layout('Layout'),
  controls('Controls'),
  shapes('Shapes'),
  text('Text'),
  menus('Menus'),
  charts('Charts'),
  misc('Misc');

  const FxCategory(this.label);
  final String label;
}

/// Description of a JavaFX component that can be placed on the canvas.
@immutable
class FxComponent {
  const FxComponent({
    required this.name,
    required this.javafxPackage,
    required this.category,
    required this.icon,
    this.isContainer = false,
    this.defaults = const <String, String>{},
  });

  final String name;
  final String javafxPackage;
  final FxCategory category;
  final IconData icon;
  final bool isContainer;
  final Map<String, String> defaults;

  String get importStatement => '$javafxPackage.$name';
}

/// Static catalog of the components offered by the editor palette.
class FxCatalog {
  const FxCatalog._();

  static const List<FxComponent> components = <FxComponent>[
    // ---------------------------------------------------------------- Layout
    FxComponent(
      name: 'AnchorPane',
      javafxPackage: 'javafx.scene.layout',
      category: FxCategory.layout,
      icon: Icons.anchor,
      isContainer: true,
      defaults: {'prefWidth': '400.0', 'prefHeight': '300.0'},
    ),
    FxComponent(
      name: 'Pane',
      javafxPackage: 'javafx.scene.layout',
      category: FxCategory.layout,
      icon: Icons.crop_square,
      isContainer: true,
      defaults: {'prefWidth': '300.0', 'prefHeight': '200.0'},
    ),
    FxComponent(
      name: 'VBox',
      javafxPackage: 'javafx.scene.layout',
      category: FxCategory.layout,
      icon: Icons.view_agenda,
      isContainer: true,
      defaults: {'spacing': '8.0'},
    ),
    FxComponent(
      name: 'HBox',
      javafxPackage: 'javafx.scene.layout',
      category: FxCategory.layout,
      icon: Icons.view_week,
      isContainer: true,
      defaults: {'spacing': '8.0'},
    ),
    FxComponent(
      name: 'StackPane',
      javafxPackage: 'javafx.scene.layout',
      category: FxCategory.layout,
      icon: Icons.layers,
      isContainer: true,
    ),
    FxComponent(
      name: 'BorderPane',
      javafxPackage: 'javafx.scene.layout',
      category: FxCategory.layout,
      icon: Icons.border_all,
      isContainer: true,
    ),
    FxComponent(
      name: 'FlowPane',
      javafxPackage: 'javafx.scene.layout',
      category: FxCategory.layout,
      icon: Icons.wrap_text,
      isContainer: true,
      defaults: {'hgap': '8.0', 'vgap': '8.0'},
    ),
    FxComponent(
      name: 'TilePane',
      javafxPackage: 'javafx.scene.layout',
      category: FxCategory.layout,
      icon: Icons.grid_view,
      isContainer: true,
      defaults: {'hgap': '8.0', 'vgap': '8.0'},
    ),
    FxComponent(
      name: 'GridPane',
      javafxPackage: 'javafx.scene.layout',
      category: FxCategory.layout,
      icon: Icons.grid_on,
      isContainer: true,
      defaults: {'hgap': '8.0', 'vgap': '8.0'},
    ),
    FxComponent(
      name: 'ScrollPane',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.layout,
      icon: Icons.swap_vert,
      isContainer: true,
      defaults: {'prefWidth': '300.0', 'prefHeight': '200.0'},
    ),
    FxComponent(
      name: 'TitledPane',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.layout,
      icon: Icons.expand_more,
      isContainer: true,
      defaults: {'text': 'Titled Pane'},
    ),
    FxComponent(
      name: 'Accordion',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.layout,
      icon: Icons.view_agenda_outlined,
      isContainer: true,
    ),
    FxComponent(
      name: 'TabPane',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.layout,
      icon: Icons.tab,
      isContainer: true,
      defaults: {'prefWidth': '300.0', 'prefHeight': '200.0'},
    ),
    FxComponent(
      name: 'SplitPane',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.layout,
      icon: Icons.vertical_split,
      isContainer: true,
      defaults: {'prefWidth': '300.0', 'prefHeight': '200.0'},
    ),
    FxComponent(
      name: 'ToolBar',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.layout,
      icon: Icons.build,
      isContainer: true,
    ),
    FxComponent(
      name: 'Group',
      javafxPackage: 'javafx.scene',
      category: FxCategory.layout,
      icon: Icons.group_work,
      isContainer: true,
    ),
    FxComponent(
      name: 'Region',
      javafxPackage: 'javafx.scene.layout',
      category: FxCategory.layout,
      icon: Icons.rectangle,
      isContainer: true,
      defaults: {'prefWidth': '120.0', 'prefHeight': '80.0'},
    ),

    // -------------------------------------------------------------- Controls
    FxComponent(
      name: 'Button',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.smart_button,
      defaults: {'text': 'Button'},
    ),
    FxComponent(
      name: 'Label',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.label,
      defaults: {'text': 'Label'},
    ),
    FxComponent(
      name: 'TextField',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.text_fields,
      defaults: {'promptText': 'Text field', 'prefWidth': '160.0'},
    ),
    FxComponent(
      name: 'TextArea',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.notes,
      defaults: {'prefWidth': '200.0', 'prefHeight': '100.0'},
    ),
    FxComponent(
      name: 'PasswordField',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.password,
      defaults: {'promptText': 'Password', 'prefWidth': '160.0'},
    ),
    FxComponent(
      name: 'CheckBox',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.check_box,
      defaults: {'text': 'CheckBox'},
    ),
    FxComponent(
      name: 'RadioButton',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.radio_button_checked,
      defaults: {'text': 'RadioButton'},
    ),
    FxComponent(
      name: 'ToggleButton',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.toggle_on,
      defaults: {'text': 'Toggle'},
    ),
    FxComponent(
      name: 'ComboBox',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.arrow_drop_down_circle,
      defaults: {'promptText': 'ComboBox', 'prefWidth': '160.0'},
    ),
    FxComponent(
      name: 'ChoiceBox',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.list_alt,
      defaults: {'prefWidth': '160.0'},
    ),
    FxComponent(
      name: 'Slider',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.tune,
      defaults: {'prefWidth': '180.0'},
    ),
    FxComponent(
      name: 'ProgressBar',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.linear_scale,
      defaults: {'progress': '0.5', 'prefWidth': '180.0'},
    ),
    FxComponent(
      name: 'ProgressIndicator',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.donut_large,
      defaults: {'progress': '0.5'},
    ),
    FxComponent(
      name: 'Separator',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.horizontal_rule,
      defaults: {'prefWidth': '200.0'},
    ),
    FxComponent(
      name: 'Hyperlink',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.link,
      defaults: {'text': 'Hyperlink'},
    ),
    FxComponent(
      name: 'ColorPicker',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.colorize,
    ),
    FxComponent(
      name: 'DatePicker',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.calendar_today,
      defaults: {'prefWidth': '160.0'},
    ),
    FxComponent(
      name: 'Spinner',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.unfold_more,
      defaults: {'prefWidth': '120.0'},
    ),
    FxComponent(
      name: 'ImageView',
      javafxPackage: 'javafx.scene.image',
      category: FxCategory.controls,
      icon: Icons.image,
      defaults: {'fitWidth': '120.0', 'fitHeight': '90.0'},
    ),
    FxComponent(
      name: 'ListView',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.view_list,
      defaults: {'prefWidth': '200.0', 'prefHeight': '150.0'},
    ),
    FxComponent(
      name: 'TableView',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.table_chart,
      defaults: {'prefWidth': '260.0', 'prefHeight': '160.0'},
    ),
    FxComponent(
      name: 'TreeView',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.controls,
      icon: Icons.account_tree,
      defaults: {'prefWidth': '200.0', 'prefHeight': '150.0'},
    ),

    // ---------------------------------------------------------------- Shapes
    FxComponent(
      name: 'Rectangle',
      javafxPackage: 'javafx.scene.shape',
      category: FxCategory.shapes,
      icon: Icons.crop_square,
      defaults: {'width': '120.0', 'height': '80.0', 'fill': '#4a90d9'},
    ),
    FxComponent(
      name: 'Circle',
      javafxPackage: 'javafx.scene.shape',
      category: FxCategory.shapes,
      icon: Icons.circle,
      defaults: {'radius': '50.0', 'fill': '#4a90d9'},
    ),
    FxComponent(
      name: 'Ellipse',
      javafxPackage: 'javafx.scene.shape',
      category: FxCategory.shapes,
      icon: Icons.egg,
      defaults: {'radiusX': '60.0', 'radiusY': '40.0', 'fill': '#4a90d9'},
    ),
    FxComponent(
      name: 'Line',
      javafxPackage: 'javafx.scene.shape',
      category: FxCategory.shapes,
      icon: Icons.horizontal_rule,
      defaults: {'startX': '0.0', 'startY': '0.0', 'endX': '120.0', 'endY': '80.0', 'stroke': '#333333'},
    ),
    FxComponent(
      name: 'Polygon',
      javafxPackage: 'javafx.scene.shape',
      category: FxCategory.shapes,
      icon: Icons.pentagon,
      defaults: {'fill': '#4a90d9'},
    ),
    FxComponent(
      name: 'Polyline',
      javafxPackage: 'javafx.scene.shape',
      category: FxCategory.shapes,
      icon: Icons.polyline,
      defaults: {'stroke': '#333333'},
    ),
    FxComponent(
      name: 'Arc',
      javafxPackage: 'javafx.scene.shape',
      category: FxCategory.shapes,
      icon: Icons.architecture,
      defaults: {'radiusX': '60.0', 'radiusY': '60.0', 'stroke': '#333333'},
    ),

    // ------------------------------------------------------------------ Text
    FxComponent(
      name: 'Text',
      javafxPackage: 'javafx.scene.text',
      category: FxCategory.text,
      icon: Icons.title,
      defaults: {'text': 'Text', 'fill': '#222222'},
    ),
    FxComponent(
      name: 'TextFlow',
      javafxPackage: 'javafx.scene.text',
      category: FxCategory.text,
      icon: Icons.notes,
      isContainer: true,
    ),

    // ----------------------------------------------------------------- Menus
    FxComponent(
      name: 'MenuBar',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.menus,
      icon: Icons.menu,
      isContainer: true,
    ),
    FxComponent(
      name: 'ContextMenu',
      javafxPackage: 'javafx.scene.control',
      category: FxCategory.menus,
      icon: Icons.more_vert,
      isContainer: true,
    ),

    // ---------------------------------------------------------------- Charts
    FxComponent(
      name: 'LineChart',
      javafxPackage: 'javafx.scene.chart',
      category: FxCategory.charts,
      icon: Icons.show_chart,
      defaults: {'prefWidth': '280.0', 'prefHeight': '180.0'},
    ),
    FxComponent(
      name: 'BarChart',
      javafxPackage: 'javafx.scene.chart',
      category: FxCategory.charts,
      icon: Icons.bar_chart,
      defaults: {'prefWidth': '280.0', 'prefHeight': '180.0'},
    ),
    FxComponent(
      name: 'PieChart',
      javafxPackage: 'javafx.scene.chart',
      category: FxCategory.charts,
      icon: Icons.pie_chart,
      defaults: {'prefWidth': '220.0', 'prefHeight': '220.0'},
    ),

    // ------------------------------------------------------------------ Misc
    FxComponent(
      name: 'Canvas',
      javafxPackage: 'javafx.scene.canvas',
      category: FxCategory.misc,
      icon: Icons.brush,
      defaults: {'width': '200.0', 'height': '150.0'},
    ),
    FxComponent(
      name: 'WebView',
      javafxPackage: 'javafx.scene.web',
      category: FxCategory.misc,
      icon: Icons.public,
      defaults: {'prefWidth': '300.0', 'prefHeight': '200.0'},
    ),
  ];

  static final Map<String, FxComponent> _byName = {
    for (final component in components) component.name: component,
  };

  /// JavaFX helper classes that appear inside property elements
  /// (`<font><Font .../></font>`, `<cursor><Cursor fx:constant=.../></cursor>`)
  /// but are not palette components. Each one still requires its own
  /// `<?import?>` statement in the FXML, otherwise JavaFX fails to load
  /// the scene with "… is not a valid type".
  static const Map<String, String> _auxiliaryImports = {
    'Font': 'javafx.scene.text.Font',
    'Cursor': 'javafx.scene.Cursor',
    'Color': 'javafx.scene.paint.Color',
    'Image': 'javafx.scene.image.Image',
    'Duration': 'javafx.util.Duration',
  };

  static FxComponent? lookup(String name) => _byName[name];

  /// Returns the import statement needed for [name], if known.
  ///
  /// Covers both palette components and auxiliary classes such as `Font`.
  static String? importFor(String name) =>
      _byName[name]?.importStatement ?? _auxiliaryImports[name];

  static List<FxComponent> byCategory(FxCategory category) =>
      components.where((c) => c.category == category).toList();

  /// Components whose default property is `children` (so they accept nested
  /// component elements directly).
  static bool isChildrenContainer(String name) {
    const containers = {
      'AnchorPane', 'Pane', 'VBox', 'HBox', 'StackPane', 'BorderPane',
      'FlowPane', 'TilePane', 'GridPane', 'Group', 'Region', 'ToolBar',
      'TextFlow', 'Accordion', 'SplitPane', 'TabPane', 'ScrollPane',
      'TitledPane',
    };
    return containers.contains(name);
  }
}
