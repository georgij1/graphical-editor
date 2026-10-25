/// Reading and building the invitation links.
///
/// The link looks like `.../#invite/<projectId>/<token>`: the project and
/// the token of the invitation are taken from the address of the page.
library;

/// An invitation taken from the address of the page.
class Invite {
  const Invite({required this.projectId, required this.token});

  final String projectId;
  final String token;
}

/// Reads the invitation from the address of the page and builds new links.
abstract class InviteLinks {
  /// The invitation found in the address of the page, if any.
  Invite? get pending;

  /// Builds the link that invites another person to the project.
  String build(String projectId, String token);
}
