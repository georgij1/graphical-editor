import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int _pbkdf2Iterations = 60000;
const int _pbkdf2KeyLength = 32;
const int _tokenTtlSeconds = 7 * 24 * 60 * 60;

final Random _random = Random.secure();

/// PBKDF2-HMAC-SHA256 used to derive a password hash for a given salt.
Uint8List pbkdf2(List<int> password, List<int> salt,
    {int iterations = _pbkdf2Iterations,
    int keyLength = _pbkdf2KeyLength}) {
  const digestLength = 32;
  final hmac = Hmac(sha256, password);
  final blockCount = (keyLength / digestLength).ceil();
  final output = BytesBuilder(copy: false);
  for (var block = 1; block <= blockCount; block++) {
    Uint8List u = Uint8List.fromList([...salt, ..._intToBe(block)]);
    u = Uint8List.fromList(hmac.convert(u).bytes);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    output.add(t);
  }
  return output.takeBytes().sublist(0, keyLength);
}

List<int> _intToBe(int value) => <int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];

String generateSalt() => base64Encode(randomBytes(16));

Uint8List randomBytes(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = _random.nextInt(256);
  }
  return bytes;
}

String hashPassword(String password, String saltB64) {
  final salt = base64Decode(saltB64);
  return base64Encode(pbkdf2(utf8.encode(password), salt));
}

bool verifyPassword(String password, String saltB64, String expectedB64) {
  final actual = hashPassword(password, saltB64);
  return constantTimeEquals(base64Decode(actual), base64Decode(expectedB64));
}

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String _b64urlEncode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

String _b64urlPad(String value) =>
    value.padRight(value.length + ((4 - value.length % 4) % 4), '=');

/// Creates a signed HS256 JWT with an [exp] claim.
String signJwt(Map<String, Object?> claims, String secret) {
  final header = _b64urlEncode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final payload = _b64urlEncode(utf8.encode(jsonEncode({
    ...claims,
    'iat': now,
    'exp': now + _tokenTtlSeconds,
  })));
  final data = utf8.encode('$header.$payload');
  final signature = _b64urlEncode(Hmac(sha256, utf8.encode(secret)).convert(data).bytes);
  return '$header.$payload.$signature';
}

/// Verifies a JWT signature and expiry. Returns the parsed claims.
Map<String, dynamic>? verifyJwt(String token, String secret) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final data = utf8.encode('${parts[0]}.${parts[1]}');
    final expected = Hmac(sha256, utf8.encode(secret)).convert(data).bytes;
    final actual = base64Url.decode(_b64urlPad(parts[2]));
    if (!constantTimeEquals(expected, actual)) return null;
    final claims = jsonDecode(
            utf8.decode(base64Url.decode(_b64urlPad(parts[1]))))
        as Map<String, dynamic>;
    final exp = claims['exp'] as int?;
    if (exp == null || exp < (DateTime.now().millisecondsSinceEpoch ~/ 1000)) {
      return null;
    }
    return claims;
  } catch (_) {
    return null;
  }
}