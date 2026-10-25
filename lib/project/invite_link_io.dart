import 'invite_link_base.dart';

/// On a desktop there is no address of the page, so the invitations are
/// passed by hand.
class PlatformInviteLinks implements InviteLinks {
  PlatformInviteLinks([this.pending]);

  @override
  final Invite? pending;

  @override
  String build(String projectId, String token) =>
      'http://localhost:8080/#invite/$projectId/$token';
}
