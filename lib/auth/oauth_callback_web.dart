import 'package:web/web.dart' as web;

import 'oauth_callback.dart';

OAuthCallbackResult readOAuthCallback() {
  final uri = Uri.parse(web.window.location.href);
  final code = uri.queryParameters['oauth_code'];
  final error = uri.queryParameters['oauth_error'];
  final provider = uri.queryParameters['oauth_provider'];
  return OAuthCallbackResult(code: code, error: error, provider: provider);
}

void clearOAuthCallbackFromUrl() {
  final uri = Uri.parse(web.window.location.href);
  if (!uri.queryParameters.containsKey('oauth_code') &&
      !uri.queryParameters.containsKey('oauth_error') &&
      !uri.queryParameters.containsKey('oauth_provider')) {
    return;
  }
  final params = Map<String, String>.from(uri.queryParameters)
    ..remove('oauth_code')
    ..remove('oauth_error')
    ..remove('oauth_provider');
  final cleaned = uri.replace(queryParameters: params.isEmpty ? null : params);
  final relative = cleaned.hasFragment
      ? '${cleaned.path}${cleaned.hasQuery ? '?${cleaned.query}' : ''}#${cleaned.fragment}'
      : '${cleaned.path}${cleaned.hasQuery ? '?${cleaned.query}' : ''}';
  web.window.history.replaceState(null, '', relative);
}
