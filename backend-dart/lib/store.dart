import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'security.dart';

class EmailTakenException implements Exception {}

class WrongPasswordException implements Exception {}

/// Largest avatar accepted, in characters of the stored data URL.
const int maxAvatarLength = 600 * 1024;

class AvatarTooLargeException implements Exception {}

class UserRecord {
  UserRecord({
    required this.id,
    required this.email,
    required this.salt,
    required this.hash,
    required this.createdAt,
    this.avatar,
  });

  final String id;
  String email;
  String salt;
  String hash;
  final DateTime createdAt;

  /// Profile picture as a `data:` URL, or null when none was uploaded.
  String? avatar;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'email': email,
        'salt': salt,
        'hash': hash,
        'createdAt': createdAt.toIso8601String(),
        if (avatar != null) 'avatar': avatar,
      };

  factory UserRecord.fromJson(Map<String, dynamic> json) => UserRecord(
        id: json['id'] as String,
        email: json['email'] as String,
        salt: json['salt'] as String,
        hash: json['hash'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        avatar: json['avatar'] as String?,
      );
}

/// Persists users and their workspaces as JSON files under [dataDir].
class UserStore {
  UserStore(this.dataDir);

  final String dataDir;
  Future<void> _lock = Future.value();

  File get _usersFile => File('$dataDir/users.json');
  Directory get _workspacesDir => Directory('$dataDir/workspaces');

  Future<void> init() async {
    await _workspacesDir.create(recursive: true);
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final previous = _lock;
    final completer = Completer<void>();
    _lock = completer.future;
    return previous.then((_) => action()).whenComplete(() => completer.complete());
  }

  Future<List<UserRecord>> _loadUsers() async {
    if (!await _usersFile.exists()) return <UserRecord>[];
    try {
      final raw = await _usersFile.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return <UserRecord>[
        for (final item in list) UserRecord.fromJson(item as Map<String, dynamic>),
      ];
    } catch (_) {
      return <UserRecord>[];
    }
  }

  Future<void> _saveUsers(List<UserRecord> users) async {
    await Directory(dataDir).create(recursive: true);
    await _usersFile
        .writeAsString(jsonEncode(<dynamic>[for (final u in users) u.toJson()]));
  }

  Future<UserRecord?> findByEmail(String email) async {
    final users = await _loadUsers();
    for (final user in users) {
      if (user.email.toLowerCase() == email.trim().toLowerCase()) return user;
    }
    return null;
  }

  Future<UserRecord?> findById(String id) async {
    final users = await _loadUsers();
    for (final user in users) {
      if (user.id == id) return user;
    }
    return null;
  }

  /// All registered accounts, so a project owner can pick the participants
  /// from the list instead of typing their addresses.
  Future<List<Map<String, dynamic>>> listAccounts() async {
    final users = await _loadUsers();
    users.sort((a, b) => a.email.compareTo(b.email));
    return <Map<String, dynamic>>[
      for (final user in users)
        <String, dynamic>{'id': user.id, 'email': user.email},
    ];
  }

  Future<UserRecord> createUser(String email, String password) {
    return _synchronized(() async {
      final users = await _loadUsers();
      for (final user in users) {
        if (user.email.toLowerCase() == email.trim().toLowerCase()) {
          throw EmailTakenException();
        }
      }
      final salt = generateSalt();
      final record = UserRecord(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        email: email.trim().toLowerCase(),
        salt: salt,
        hash: hashPassword(password, salt),
        createdAt: DateTime.now().toUtc(),
      );
      users.add(record);
      await _saveUsers(users);
      return record;
    });
  }

  /// Changes the login (email). The address must not belong to someone else.
  Future<UserRecord> updateEmail(String userId, String email) {
    return _synchronized(() async {
      final normalized = email.trim().toLowerCase();
      final users = await _loadUsers();
      UserRecord? target;
      for (final user in users) {
        if (user.id == userId) {
          target = user;
        } else if (user.email.toLowerCase() == normalized) {
          throw EmailTakenException();
        }
      }
      if (target == null) throw StateError('Unknown user $userId');
      target.email = normalized;
      await _saveUsers(users);
      return target;
    });
  }

  /// Re-hashes the password after verifying the current one.
  Future<UserRecord> updatePassword(
      String userId, String currentPassword, String newPassword) {
    return _synchronized(() async {
      final users = await _loadUsers();
      UserRecord? target;
      for (final user in users) {
        if (user.id == userId) target = user;
      }
      if (target == null) throw StateError('Unknown user $userId');
      if (!verifyPassword(currentPassword, target.salt, target.hash)) {
        throw WrongPasswordException();
      }
      final salt = generateSalt();
      target
        ..salt = salt
        ..hash = hashPassword(newPassword, salt);
      await _saveUsers(users);
      return target;
    });
  }

  /// Stores (or clears, when [avatar] is null) the profile picture.
  Future<UserRecord> updateAvatar(String userId, String? avatar) {
    if (avatar != null && avatar.length > maxAvatarLength) {
      throw AvatarTooLargeException();
    }
    return _synchronized(() async {
      final users = await _loadUsers();
      UserRecord? target;
      for (final user in users) {
        if (user.id == userId) target = user;
      }
      if (target == null) throw StateError('Unknown user $userId');
      target.avatar = avatar;
      await _saveUsers(users);
      return target;
    });
  }

  Future<String?> readWorkspace(String userId) async {
    final file = File('${_workspacesDir.path}/$userId.json');
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> writeWorkspace(String userId, String json) {
    return _synchronized(() async {
      await _workspacesDir.create(recursive: true);
      await File('${_workspacesDir.path}/$userId.json')
          .writeAsString(json, flush: true);
    });
  }
}