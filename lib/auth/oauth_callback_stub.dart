import 'oauth_callback.dart';

OAuthCallbackResult readOAuthCallback() {
  // Non-web: no browser URL callback.
  return const OAuthCallbackResult();
}

void clearOAuthCallbackFromUrl() {}
