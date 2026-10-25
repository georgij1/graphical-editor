import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/l10n/app_localizations.dart';
import 'package:graphical_editor/ui/widgets/profile_dialog.dart';
import 'package:graphical_editor/ui/widgets/user_avatar.dart';

import 'test_doubles.dart';

/// A 1x1 transparent PNG.
final Uint8List _tinyPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

String _base64(List<int> bytes) => base64Encode(bytes);

/// A tall surface keeps the whole dialog on screen, so its buttons stay
/// reachable behind the action bar.
void _room(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The dialog scrolls, so its buttons have to be brought into view first.
Future<void> _tapDialogButton(WidgetTester tester, String label) async {
  final target = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<(EditorController, FakeApiClient)> _signedIn() async {
  final api = FakeApiClient();
  final controller = EditorController(
    storage: InMemoryProjectStorage(),
    tokenStore: InMemoryKeyValueStore(),
    api: api,
  );
  await controller.register('user@example.com', 'secret1');
  return (controller, api);
}

void main() {
  group('profile in the controller', () {
    test('the login can be changed', () async {
      final (controller, api) = await _signedIn();

      final ok = await controller.updateEmail('  new@example.com ');

      expect(ok, isTrue);
      expect(controller.userEmail, 'new@example.com');
      expect(api.lastEmailChange, 'user@example.com -> new@example.com');
      expect(controller.profileError, isFalse);
    });

    test('an unchanged login is not sent', () async {
      final (controller, api) = await _signedIn();

      final ok = await controller.updateEmail('user@example.com');

      expect(ok, isFalse);
      expect(api.lastEmailChange, isNull);
      expect(controller.profileMessage, 'The login is unchanged.');
    });

    test('a taken login reports the server error', () async {
      final (controller, api) = await _signedIn();
      api.seedUser('other@example.com', 'secret2');

      final ok = await controller.updateEmail('other@example.com');

      expect(ok, isFalse);
      expect(controller.profileError, isTrue);
      expect(controller.profileMessage, 'This email is already registered.');
      expect(controller.userEmail, 'user@example.com');
    });

    test('the password can be changed', () async {
      final (controller, _) = await _signedIn();

      expect(await controller.changePassword('secret1', 'brand-new'), isTrue);
      expect(controller.profileMessage, 'Password changed.');
      // The new credentials really work.
      final api = FakeApiClient();
      final other = EditorController(
        storage: InMemoryProjectStorage(),
        tokenStore: InMemoryKeyValueStore(),
        api: api,
      );
      expect(api, isNotNull);
      expect(other.authStatus, AuthStatus.loading);
    });

    test('a wrong current password is rejected', () async {
      final (controller, _) = await _signedIn();

      final ok = await controller.changePassword('nope', 'brand-new');

      expect(ok, isFalse);
      expect(controller.profileError, isTrue);
      expect(controller.profileMessage, 'Current password is incorrect.');
    });

    test('an avatar can be uploaded and removed', () async {
      final (controller, api) = await _signedIn();

      expect(await controller.uploadAvatar(_tinyPng, mimeType: 'image/png'),
          isTrue);
      expect(controller.avatarDataUrl, startsWith('data:image/png;base64,'));
      expect(api.avatarFor('user@example.com'), isNotNull);

      expect(await controller.removeAvatar(), isTrue);
      expect(controller.avatarDataUrl, isNull);
    });

    test('an oversized picture is refused before uploading', () async {
      final (controller, api) = await _signedIn();

      final ok = await controller.uploadAvatar(
        Uint8List(EditorController.maxAvatarBytes + 1),
        mimeType: 'image/png',
      );

      expect(ok, isFalse);
      expect(controller.profileMessage, 'The picture is too large.');
      expect(api.avatarFor('user@example.com'), isNull);
    });

    test('the avatar is restored from storage on the next start', () async {
      final store = InMemoryKeyValueStore();
      final api = FakeApiClient();
      final first = EditorController(
        storage: InMemoryProjectStorage(),
        tokenStore: store,
        api: api,
      );
      await first.register('user@example.com', 'secret1');
      await first.uploadAvatar(_tinyPng, mimeType: 'image/png');

      final restarted = EditorController(
        storage: InMemoryProjectStorage(),
        tokenStore: store,
        api: api,
      );
      await restarted.initAuth();

      expect(restarted.avatarDataUrl, startsWith('data:image/png;base64,'));
    });
  });

  group('profile dialog', () {
    Widget app(EditorController controller, {Locale locale = const Locale('en')}) {
      return MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    showProfileDialog(context, controller: controller),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows the login and the password fields',
        (tester) async {
      _room(tester);
      final (controller, _) = await _signedIn();
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);
      expect(find.text('Current password'), findsOneWidget);
      expect(find.text('New password'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(find.text('Choose picture'), findsOneWidget);
    });

    testWidgets('mismatched passwords are reported before the request',
        (tester) async {
      _room(tester);
      final (controller, _) = await _signedIn();
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Current password'), 'secret1');
      await tester.enterText(
          find.widgetWithText(TextField, 'New password'), 'abcdef');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm password'), 'abcdefg');
      await _tapDialogButton(tester, 'Change password');

      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(controller.profileMessage, isNull);
    });

    testWidgets('a short password is rejected locally', (tester) async {
      _room(tester);
      final (controller, _) = await _signedIn();
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'New password'), 'abc');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm password'), 'abc');
      await _tapDialogButton(tester, 'Change password');

      expect(find.text('Password must be at least 6 characters.'),
          findsOneWidget);
    });

    testWidgets('changing the login updates the dialog', (tester) async {
      _room(tester);
      final (controller, _) = await _signedIn();
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'renamed@example.com');
      await _tapDialogButton(tester, 'Save');

      expect(controller.userEmail, 'renamed@example.com');
      expect(find.text('Login updated.'), findsOneWidget);
    });

    testWidgets('the dialog is translated', (tester) async {
      _room(tester);
      final (controller, _) = await _signedIn();
      await tester.pumpWidget(app(controller, locale: const Locale('ru')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Профиль'), findsOneWidget);
      expect(find.text('Логин'), findsOneWidget);
      expect(find.text('Текущий пароль'), findsOneWidget);
      expect(find.text('Сменить пароль'), findsOneWidget);
      expect(find.text('Выбрать фото'), findsOneWidget);
    });
  });

  group('UserAvatar', () {
    testWidgets('falls back to the first letter of the login',
        (tester) async {
      _room(tester);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: UserAvatar(dataUrl: null, email: 'zoe@example.com')),
      ));
      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('renders the uploaded picture', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UserAvatar(
            dataUrl: 'data:image/png;base64,${_base64(_tinyPng)}',
            email: 'zoe@example.com',
          ),
        ),
      ));
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Z'), findsNothing);
    });

    testWidgets('survives a broken picture', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: UserAvatar(dataUrl: 'data:image/png;base64,zz')),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
