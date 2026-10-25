import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/fxml/fxml_parser.dart';
import 'package:graphical_editor/render/fx_renderer.dart';

const _document = '''
<?xml version="1.0" encoding="UTF-8"?>
<?import javafx.scene.layout.*?>
<?import javafx.scene.control.*?>
<?import javafx.scene.shape.*?>
<AnchorPane xmlns="http://javafx.com/javafx/17.0.2" prefWidth="800.0" prefHeight="600.0">
    <children>
        <VBox spacing="8.0" layoutX="20.0" layoutY="20.0">
            <children>
                <Label text="Title"/>
                <Button text="Click"/>
                <TextField promptText="Type here"/>
                <CheckBox text="Agree"/>
                <RadioButton text="Choice"/>
                <Slider prefWidth="150.0"/>
                <ProgressBar progress="0.4" prefWidth="150.0"/>
                <Separator prefWidth="150.0"/>
                <ComboBox promptText="Pick"/>
                <Hyperlink text="Link"/>
            </children>
        </VBox>
        <HBox spacing="10.0" layoutX="300.0" layoutY="20.0">
            <children>
                <Rectangle width="80.0" height="60.0" fill="#4a90d9"/>
                <Circle radius="30.0" fill="#e57373"/>
                <Ellipse radiusX="40.0" radiusY="24.0" fill="#6fbf73"/>
            </children>
        </HBox>
        <StackPane layoutX="300.0" layoutY="150.0" prefWidth="200.0" prefHeight="120.0">
            <children>
                <Label text="Stacked"/>
            </children>
        </StackPane>
        <BorderPane layoutX="20.0" layoutY="300.0" prefWidth="300.0" prefHeight="180.0">
            <top>
                <Label text="Top"/>
            </top>
            <center>
                <Label text="Center"/>
            </center>
            <bottom>
                <Label text="Bottom"/>
            </bottom>
        </BorderPane>
        <GridPane layoutX="350.0" layoutY="300.0">
            <children>
                <Label text="A" GridPane.rowIndex="0" GridPane.columnIndex="0"/>
                <Label text="B" GridPane.rowIndex="0" GridPane.columnIndex="1"/>
                <Label text="C" GridPane.rowIndex="1" GridPane.columnIndex="0"/>
            </children>
        </GridPane>
        <TabPane layoutX="20.0" layoutY="500.0" prefWidth="260.0" prefHeight="80.0">
            <tabs>
                <Tab text="One">
                    <content>
                        <Label text="Tab content"/>
                    </content>
                </Tab>
                <Tab text="Two"/>
            </tabs>
        </TabPane>
    </children>
</AnchorPane>
''';

void main() {
  testWidgets('renders a rich document without errors', (tester) async {
    final document = const FxmlParser().parse(_document);
    const context = FxRenderContext(
      canvasSize: Size(800, 600),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 900,
              height: 700,
              child: FxRenderer(context).build(document.root),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Click'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Tab content'), findsOneWidget);
  });
}
