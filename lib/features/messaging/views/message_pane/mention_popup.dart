part of 'message_pane.dart';

/// Compact "@" autocomplete popup rendered above the composer. Lists
/// members of [spaceId] (and mentionable roles) whose name starts with —
/// or contains — [query]; tapping inserts the handle into the composer via
/// [onPick]. Hidden automatically by the composer when [query] becomes
/// empty of matches.
class _MentionPopup extends ConsumerWidget {
  const _MentionPopup({
    required this.spaceId,
    required this.query,
    required this.allowBroadcast,
    required this.onPick,
  });

  final String spaceId;
  final String query;
  final bool allowBroadcast;
  final ValueChanged<String> onPick;

  static const int _maxResults = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final members = ref.watch(accordMembersControllerProvider(ref.readActiveServerKey() ?? '', spaceId));
    final space = ref.watch(
      spacesControllerProvider.select(
        (s) => s?.firstWhereOrNull((sp) => sp.id == spaceId),
      ),
    );
    final roles = space?.roles ?? const <AccordRole>[];
    final entries = _filter(members, roles, query);
    if (entries.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.foreground, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in entries)
            InkWell(
              onTap: () => onPick(entry.handle),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(
                      switch (entry.kind) {
                        _MentionEntryKind.broadcast => Icons.campaign_outlined,
                        _MentionEntryKind.member => Icons.person,
                        _MentionEntryKind.role => Icons.label_outline,
                      },
                      size: 14,
                      color: entry.kind == _MentionEntryKind.broadcast
                          ? _composerBroadcastColor
                          : colors.gray,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: entry.kind == _MentionEntryKind.broadcast
                              ? _composerBroadcastColor
                              : null,
                        ),
                      ),
                    ),
                    Text(
                      "@${entry.handle}",
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall!.copyWith(
                        color: entry.kind == _MentionEntryKind.broadcast
                            ? _composerBroadcastColor
                            : colors.gray,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Picks up to [_maxResults] candidates from broadcast mentions, members and
  /// mentionable roles whose handle/label matches [query] (case-insensitive).
  /// Broadcast mentions always rank first, then prefix before substring
  /// matches for members and roles.
  List<_MentionEntry> _filter(
    Map<String, AccordMember>? members,
    List<AccordRole> roles,
    String query,
  ) {
    final q = query.toLowerCase();
    final broadcasts = <_MentionEntry>[];
    final prefix = <_MentionEntry>[];
    final contains = <_MentionEntry>[];
    void consider(_MentionEntry e, {bool broadcast = false}) {
      final h = e.handle.toLowerCase();
      final l = e.label.toLowerCase();
      if (q.isEmpty || h.startsWith(q) || l.startsWith(q)) {
        (broadcast ? broadcasts : prefix).add(e);
      } else if (h.contains(q) || l.contains(q)) {
        (broadcast ? broadcasts : contains).add(e);
      }
    }

    if (allowBroadcast) {
      consider(
        const _MentionEntry(
          handle: 'everyone',
          label: 'Notify everyone',
          kind: _MentionEntryKind.broadcast,
        ),
        broadcast: true,
      );
      consider(
        const _MentionEntry(
          handle: 'here',
          label: 'Notify online members',
          kind: _MentionEntryKind.broadcast,
        ),
        broadcast: true,
      );
    }

    if (members != null) {
      for (final m in members.values) {
        final user = m.user;
        final username = user?.username;
        if (username == null || username.isEmpty) continue;
        consider(
          _MentionEntry(
            handle: username,
            label: accordMemberName(m, fallback: username),
            kind: _MentionEntryKind.member,
          ),
        );
      }
    }
    for (final r in roles) {
      if (!r.mentionable) continue;
      consider(
        _MentionEntry(
          handle: r.name,
          label: r.name,
          kind: _MentionEntryKind.role,
        ),
      );
    }
    final out = [...broadcasts, ...prefix, ...contains];
    if (out.length > _maxResults) return out.sublist(0, _maxResults);
    return out;
  }
}

class _MentionEntry {
  const _MentionEntry({
    required this.handle,
    required this.label,
    required this.kind,
  });
  final String handle;
  final String label;
  final _MentionEntryKind kind;
}

enum _MentionEntryKind { broadcast, member, role }

/// Matches the broadcast chip used by sent-message markup.
const _composerBroadcastColor = Color(0xFFFAA61A);
