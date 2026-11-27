import 'oauth_callback_stub.dart'
    if (dart.library.js_interop) 'oauth_callback_web.dart' as impl;

class OAuthCallbackResult {
  const OAuthCallbackResult({this.code, this.error, this.provider});

  final String? code;
  final String? error;
  final String? provider;

  bool get hasCode => code != null && code!.isNotEmpty;
  bool get hasError => error != null && error!.isNotEmpty;
  bool get isEmpty => !hasCode && !hasError;
}

OAuthCallbackResult readOAuthCallback() => impl.readOAuthCallback();

void clearOAuthCallbackFromUrl() => impl.clearOAuthCallbackFromUrl();
