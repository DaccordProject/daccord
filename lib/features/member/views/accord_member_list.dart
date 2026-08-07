import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/member/views/accord_member_popout.dart';
import 'package:bonfire/features/member/views/remote_origin_badge.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/server_unreachable.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The right-hand member roster for the Accord home view. Groups the space's
/// cached members under their highest hoisted role (ungrouped members fall into
/// a trailing "Members" section), tinting each name by its highest colored
/// role. The Accord analogue of Bonfire's firebridge `MemberList`/
/// `MemberScrollView`, but driven by the simpler [AccordMembersController]
/// cache rather than Discord's lazy member-list sync ranges.
class AccordMemberList extends ConsumerWidget {
  const AccordMemberList({super.key, required this.spaceId});

  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final id = spaceId;

    final body = id == null
        ? const SizedBox.shrink()
        : _Roster(spaceId: id);

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: colors.foreground,
        border: Border(left: BorderSide(color: colors.background, width: 1)),
      ),
      child: body,
    );
  }
}

class _Roster extends ConsumerWidget {
  const _Roster({required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(accordMembersControllerProvider(spaceId));
    final roles = ref.watch(
      spacesControllerProvider.select(
        (spaces) =>
            spaces?.firstWhereOrNull((s) => s.id == spaceId)?.roles ??
            const <AccordRole>[],
      ),
    );
    final cdnUrl = ref.watchCdnUrl();
    final presences = ref.watch(activePresencesProvider);

    if (members == null) {
      // The roster fetch itself failed (timeout / non-2xx / network) — surface
      // a retry instead of spinning forever. onRetry clears the failed flag
      // itself, then invalidates the controller to re-run `_load`.
      if (ref.watch(membersLoadFailedProvider(spaceId))) {
        return ServerUnreachable(
          title: "Couldn't load members",
          message: 'Something went wrong fetching the member list.',
          onRetry: () {
            ref.read(membersLoadFailedProvider(spaceId).notifier).set(false);
            ref.invalidate(accordMembersControllerProvider(spaceId));
          },
        );
      }
      if (ref.watch(connectionControllerProvider).isUnreachable) {
        return ServerUnreachable(onRetry: () {
          final auth = ref.read(accordAuthProvider);
          if (auth is AccordAuthLoggedIn) {
            auth.client.ensureConnected();
          }
        });
      }
      return const LoadingView();
    }

    final sections = _buildSections(members.values.toList(), roles, presences);

    // Flatten sections into one lazily-built row list so a large roster only
    // materializes the rows on screen.
    final rows = <Widget Function()>[
      for (final section in sections) ...[
        () => _SectionHeader(
              label: section.label,
              count: section.members.length,
            ),
        for (final member in section.members)
          () => _MemberRow(
                member: member,
                roles: roles,
                cdnUrl: cdnUrl,
                spaceId: spaceId,
                status: accordPresenceStatus(presences, member.userId),
              ),
      ],
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](),
    );
  }
}

/// One roster group: a hoisted role's members, or the trailing default bucket.
class _RosterSection {
  _RosterSection({required this.label, required this.position})
      : members = [];

  final String label;

  /// Role position for ordering; the default bucket uses [_defaultPosition] so
  /// it always sorts last.
  final int position;
  final List<AccordMember> members;
}

const int _defaultPosition = -1;
const int _offlinePosition = -2;

/// Buckets online [members] under their highest hoisted role (falling back to a
/// "Members" group); all offline members collapse into a single trailing
/// "Offline" section (Discord-style). Sections sort by role position descending,
/// then "Members", then "Offline" last; members within a section sort by name.
List<_RosterSection> _buildSections(
  List<AccordMember> members,
  List<AccordRole> roles,
  PresenceMap presences,
) {
  final byKey = <String, _RosterSection>{};
  final defaultSection =
      _RosterSection(label: 'Members', position: _defaultPosition);
  final offlineSection =
      _RosterSection(label: 'Offline', position: _offlinePosition);

  for (final member in members) {
    if (accordPresenceStatus(presences, member.userId) == 'offline') {
      offlineSection.members.add(member);
      continue;
    }
    final role = memberHoistRole(member, roles);
    if (role == null) {
      defaultSection.members.add(member);
      continue;
    }
    final section = byKey.putIfAbsent(
      role.id,
      () => _RosterSection(label: role.name, position: role.position),
    );
    section.members.add(member);
  }

  final sections = byKey.values.toList()
    ..sort((a, b) => b.position.compareTo(a.position));
  if (defaultSection.members.isNotEmpty) sections.add(defaultSection);
  if (offlineSection.members.isNotEmpty) sections.add(offlineSection);

  for (final section in sections) {
    section.members.sort((a, b) => accordMemberName(a)
        .toLowerCase()
        .compareTo(accordMemberName(b).toLowerCase()));
  }
  return sections;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        '${label.toUpperCase()} — $count',
        style: Theme.of(context)
            .textTheme
            .labelSmall!
            .copyWith(color: colors.gray, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.member,
    required this.roles,
    required this.cdnUrl,
    required this.spaceId,
    required this.status,
  });

  final AccordMember member;
  final List<AccordRole> roles;
  final String? cdnUrl;
  final String spaceId;
  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final name = accordMemberName(member);
    final avatarUrl = accordMemberAvatarUrl(member, cdnUrl);
    final colorRole = memberColorRole(member, roles);
    final nameColor =
        colorRole == null ? colors.dirtyWhite : accordRoleColor(colorRole.color);
    final initial = accordInitial(name);
    // Offline members read as muted, matching the reference roster.
    final dimmed = status == 'offline';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showAccordMemberPopout(
            context,
            spaceId: spaceId,
            userId: member.userId,
          ),
          onSecondaryTapUp: (d) => _showMemberContextMenu(
            context,
            ref,
            member,
            spaceId,
            d.globalPosition,
          ),
          onLongPress: () => _showMemberContextMenu(
            context,
            ref,
            member,
            spaceId,
            null,
          ),
          child: Opacity(
            opacity: dimmed ? 0.5 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  AccordMemberAvatar(
                    avatarUrl: avatarUrl,
                    initial: initial,
                    status: status,
                    radius: 16,
                    backgroundColor:
                        accordAvatarColor(member.user, member.userId),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium!
                          .copyWith(color: nameColor ?? colors.dirtyWhite),
                    ),
                  ),
                  if (member.isRemote) ...[
                    const SizedBox(width: 6),
                    RemoteOriginBadge(
                      domain: member.homeDomain,
                      showDomain: false,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick-utility right-click / long-press menu for a roster member: view their
/// profile, start a DM, or copy their id/username. Moderation lives in the
/// profile popout reached by tapping the row. [globalPos] is the pointer
/// location for a right-click; it's null for a long-press, where the menu
/// anchors to the overlay centre instead.
Future<void> _showMemberContextMenu(
  BuildContext context,
  WidgetRef ref,
  AccordMember member,
  String spaceId,
  Offset? globalPos,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  final anchor = globalPos ?? overlay.size.center(Offset.zero);
  final currentUserId = ref.readUserId();
  final isSelf = currentUserId != null && currentUserId == member.userId;
  final username = member.user?.username;
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      anchor & const Size(40, 40),
      Offset.zero & overlay.size,
    ),
    items: [
      const PopupMenuItem(value: 'profile', child: Text('View Profile')),
      if (!isSelf)
        const PopupMenuItem(value: 'dm', child: Text('Direct Message')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'copyId', child: Text('Copy User ID')),
      if (username != null && username.isNotEmpty)
        const PopupMenuItem(value: 'copyName', child: Text('Copy Username')),
    ],
  );
  if (selected == null || !context.mounted) return;
  switch (selected) {
    case 'profile':
      await showAccordMemberPopout(
        context,
        spaceId: spaceId,
        userId: member.userId,
      );
    case 'dm':
      await openAccordDirectMessage(context, ref, member.userId);
    case 'copyId':
      await Clipboard.setData(ClipboardData(text: member.userId));
      if (context.mounted) _toast(context, 'User ID copied');
    case 'copyName':
      await Clipboard.setData(ClipboardData(text: username!));
      if (context.mounted) _toast(context, 'Username copied');
  }
}

void _toast(BuildContext context, String message) {
  if (!context.mounted) return;
  showInfoSnack(context, message);
}
