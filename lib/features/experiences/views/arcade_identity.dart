import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/shared/components/ticker_aware_circle_avatar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ArcadeIdentity = ({String name, String? avatarUrl, Color color});

ArcadeIdentity watchArcadeIdentity(
  WidgetRef ref, {
  required String serverKey,
  required String spaceId,
  required String userId,
}) {
  final member = ref.watch(
    accordMembersControllerProvider(
      serverKey,
      spaceId,
    ).select((m) => m?[userId]),
  );
  final cached = ref.watch(
    accordUsersControllerProvider(serverKey).select((users) => users[userId]),
  );
  final user = member?.user ?? cached;
  if (user == null) {
    ref.read(accordUsersControllerProvider(serverKey).notifier).ensure(userId);
  }
  final account = ref.watch(
    connectionsControllerProvider.select(
      (s) => s.connectionFor(serverKey)?.session,
    ),
  );
  final fallback = account?.userId == userId ? account!.username : 'Player';
  return (
    name: member?.nickname?.isNotEmpty == true
        ? member!.nickname!
        : accordUserName(user, fallback: fallback),
    avatarUrl: accordAuthorAvatarUrlOf(
      member: member,
      user: user,
      cdnUrl: account?.server.cdnUrl,
    ),
    color: accordAvatarColor(user, userId),
  );
}

class ArcadePlayerAvatar extends StatelessWidget {
  const ArcadePlayerAvatar({
    super.key,
    required this.identity,
    this.radius = 14,
  });
  final ArcadeIdentity identity;
  final double radius;
  @override
  Widget build(BuildContext context) => TickerAwareCircleAvatar(
    radius: radius,
    backgroundColor: identity.color,
    foregroundImage: identity.avatarUrl == null
        ? null
        : CachedNetworkImageProvider(identity.avatarUrl!),
    child: Text(
      accordInitial(identity.name),
      style: TextStyle(fontSize: radius, color: accordOnColor(identity.color)),
    ),
  );
}
