import 'invite_link_base.dart';
import 'invite_link_io.dart'
    if (dart.library.js_interop) 'invite_link_web.dart';

export 'invite_link_base.dart';

InviteLinks createInviteLinks() => PlatformInviteLinks();
