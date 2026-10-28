import 'dart:io';

import 'package:fxml_editor_backend/api.dart';
import 'package:fxml_editor_backend/history_store.dart';
import 'package:fxml_editor_backend/project_store.dart';
import 'package:fxml_editor_backend/store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

const _devSecret = 'dev-secret-change-me-in-production';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final secret = Platform.environment['JWT_SECRET'] ?? _devSecret;
  final dataDir =
      Platform.environment['DATA_DIR'] ?? '${Directory.current.path}/data';

  final store = UserStore(dataDir);
  await store.init();

  // The projects that several accounts work on together.
  final projects = ProjectStore(dataDir);
  await projects.init();

  // The released versions and the builds of the projects.
  final history = HistoryStore(dataDir);
  await history.init();

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(buildHandler(
          secret: secret, store: store, projects: projects, history: history));

  await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('FXML editor backend listening on http://localhost:$port');
  stdout.writeln('Data directory: $dataDir');
}