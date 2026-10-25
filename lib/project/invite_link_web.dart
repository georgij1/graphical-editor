import 'package:web/web.dart' as web;

import 'invite_link_base.dart';

class PlatformInviteLinks implements InviteLinks {
  @override
  Invite? get pending {
    final hash = web.window.location.hash;
    if (hash.isEmpty) return null;
    // #invite/<projectId>/<token>
    final parts = hash.replaceFirst('#', '').split('/');
    if (parts.length < 3 || parts[0] != 'invite') return null;
    if (parts[1].isEmpty || parts[2].isEmpty) return null;
    return Invite(projectId: parts[1], token: parts[2]);
  }

  @override
  String build(String projectId, String token) {
    final origin = web.window.location.origin;
    final path = web.window.location.pathname;
    return '$origin$path#invite/$projectId/$token';
  }
}
