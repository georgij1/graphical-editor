/// Build identifier stamped in at compile time, so a running client can prove
/// which bundle it was served. Set it in the Dockerfile:
/// `--dart-define=BUILD_ID=<timestamp>`.
const String buildId = String.fromEnvironment(
  'BUILD_ID',
  defaultValue: 'dev',
);