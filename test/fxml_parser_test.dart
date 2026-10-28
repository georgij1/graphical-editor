import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/fxml/fxml_parser.dart';
import 'package:graphical_editor/fxml/fxml_serializer.dart';

const _sample = '''
<?xml version="1.0" encoding="UTF-8"?>
<?import javafx.scene.control.Button?>
<?import javafx.scene.layout.AnchorPane?>
<?import javafx.scene.text.Font?>
<?import javafx.scene.Cursor?>
<AnchorPane xmlns="http://javafx.com/javafx/17.0.2" xmlns:fx="http://javafx.com/fxml/1" prefWidth="800.0" prefHeight="600.0">
    <children>
        <Button fx:id="okButton" text="OK" layoutX="40.0" layoutY="30.0"/>
        <Label text="Hello">
            <font>
                <Font size="18.0"/>
            </font>
        </Label>
    </children>
</AnchorPane>
''';

void main() {
  group('FxmlParser', () {
    test('parses root, attributes and children', () {
      final doc = const FxmlParser().parse(_sample);
      expect(doc.imports, contains('javafx.scene.control.Button'));
      expect(doc.imports, contains('javafx.scene.text.Font'));
      expect(doc.imports, contains('javafx.scene.Cursor'));
      expect(doc.root.tag, 'AnchorPane');
      expect(doc.root.attributes['prefWidth'], '800.0');
      expect(doc.root.attributes['xmlns:fx'], 'http://javafx.com/fxml/1');
      expect(doc.root.children.length, 2);
      expect(doc.root.children.first.tag, 'Button');
      expect(doc.root.children.first.fxId, 'okButton');
      expect(doc.root.children.first.parent, doc.root);
    });

    test('parses property elements', () {
      final doc = const FxmlParser().parse(_sample);
      final label = doc.root.children.last;
      expect(label.tag, 'Label');
      expect(label.properties.containsKey('font'), isTrue);
      final font = label.properties['font']!;
      expect(font.tag, 'font');
      expect(font.isProperty, isTrue);
      expect(font.children.single.tag, 'Font');
      expect(font.children.single.attributes['size'], '18.0');
    });
  });

  group('FxmlSerializer', () {
    test('round-trips a document without losing information', () {
      final parser = const FxmlParser();
      final serializer = const FxmlSerializer();
      final doc = parser.parse(_sample);
      final output = serializer.serialize(doc);
      final reparsed = parser.parse(output);

      expect(reparsed.root.tag, doc.root.tag);
      expect(reparsed.imports, doc.imports);
      expect(reparsed.root.children.length, doc.root.children.length);
      expect(reparsed.root.children.first.attributes, doc.root.children.first.attributes);
      expect(
        reparsed.root.children.last.properties['font']!.children.single.attributes,
        {'size': '18.0'},
      );
    });
  });
}
