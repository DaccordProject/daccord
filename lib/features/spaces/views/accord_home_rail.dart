part of 'accord_home.dart';

class _SpaceRail extends ConsumerWidget {
  const _SpaceRail({
    required this.selectedSpaceId,
    required this.onSelect,
    required this.onAddServer,
    required this.onSwitchAccount,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final String? selectedSpaceId;

  /// Called with the owning server's connection key and the selected space id.
  final void Function(String serverKey, String spaceId) onSelect;
  final VoidCallback onAddServer;
  final VoidCallback onSwitchAccount;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final connections = ref.watch(connectionsControllerProvider);
    final activeKey = connections.activeKey;
    // The active connection's authoritative, live space list (includes spaces
    // just joined via discovery before a gateway event arrives).
    final liveActiveSpaces = ref.watch(spacesControllerProvider);
    final multi = connections.hasMultiple;

    final railItems = <Widget>[];
    for (final conn in connections.connections) {
      final isActive = conn.key == activeKey;
      final spaces = isActive ? (liveActiveSpaces ?? conn.spaces) : conn.spaces;
      final cdnUrl = conn.session.server.cdnUrl;

      if (multi) {
        railItems.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 2),
            child: _ServerGroupHeader(
              name: conn.session.server.name ?? conn.session.server.baseUrl,
              status: conn.status,
              active: isActive,
            ),
          ),
        );
      }

      for (final space in spaces) {
        railItems.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _SpaceIcon(
              space: space,
              selected: isActive && space.id == selectedSpaceId,
              cdnUrl: cdnUrl,
              onTap: () => onSelect(conn.key, space.id),
            ),
          ),
        );
      }
    }

    railItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _AddServerButton(onTap: onAddServer),
      ),
    );

    return Container(
      width: 72,
      color: colors.background,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: railItems,
            ),
          ),
          IconButton(
            tooltip: 'Direct messages',
            onPressed: () => showAccordDirectMessages(context),
            icon: Icon(Icons.chat_bubble_outline,
                size: 20, color: colors.dirtyWhite),
          ),
          IconButton(
            tooltip: 'Explore public spaces',
            onPressed: () => showAccordDiscovery(context),
            icon: Icon(Icons.explore, size: 22, color: colors.dirtyWhite),
          ),
          const SelfStatusButton(),
          IconButton(
            tooltip: 'Switch account',
            onPressed: onSwitchAccount,
            icon: Icon(Icons.switch_account, color: colors.dirtyWhite, size: 20),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: Icon(Icons.settings, color: colors.dirtyWhite, size: 20),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: onLogout,
            icon: Icon(Icons.logout, color: colors.dirtyWhite, size: 20),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SpaceIcon extends ConsumerWidget {
  const _SpaceIcon({
    required this.space,
    required this.selected,
    required this.cdnUrl,
    required this.onTap,
  });

  final AccordSpace space;
  final bool selected;
  final String? cdnUrl;
  final VoidCallback onTap;

  String get _initials {
    final name = space.name.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final iconUrl = _spaceIconUrl(space, cdnUrl);
    // Roll up per-channel read state into a single rail-level indicator. We
    // only consider channels we've already loaded — the rail doesn't force a
    // fetch for every server just to compute a badge.
    final readState = ref.watch(readStateControllerProvider);
    final channels = ref.watch(accordChannelsControllerProvider(space.id)) ??
        const <AccordChannel>[];
    final channelIds = channels.map((c) => c.id);
    final hasUnread = !selected && readState.anyUnread(channelIds);
    final mentions = readState.mentionsAcross(channelIds);
    final radius = BorderRadius.circular(selected ? 16 : 24);
    final fallback = Text(
      _initials,
      style:
          Theme.of(context).textTheme.titleSmall!.copyWith(color: Colors.white),
    );
    return Center(
      child: Tooltip(
        message: space.name,
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 48,
                height: 48,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: selected ? colors.primary : colors.darkGray,
                  borderRadius: radius,
                ),
                alignment: Alignment.center,
                child: iconUrl == null
                    ? fallback
                    : CachedNetworkImage(
                        imageUrl: iconUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => fallback,
                        errorWidget: (_, _, _) => fallback,
                      ),
              ),
              if (mentions > 0)
                Positioned(
                  right: -4,
                  top: -2,
                  child: _MentionBadge(count: mentions),
                )
              else if (hasUnread)
                Positioned(
                  left: -4,
                  top: 18,
                  child: Container(
                    width: 8,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A slim per-server separator shown in the rail only when more than one server
/// is connected: the server's initial, its name as a tooltip, and a status dot.
class _ServerGroupHeader extends StatelessWidget {
  const _ServerGroupHeader({
    required this.name,
    required this.status,
    required this.active,
  });

  final String name;
  final ConnectionStatus status;
  final bool active;

  Color get _statusColor {
    switch (status) {
      case ConnectionStatus.ready:
      case ConnectionStatus.connected:
        return const Color(0xFF43B581);
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        return const Color(0xFFFAA61A);
      case ConnectionStatus.disconnected:
        return const Color(0xFFF04747);
    }
  }

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: Tooltip(
        message: name,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colors.darkGray,
            shape: BoxShape.circle,
            border: active
                ? Border.all(color: colors.primary, width: 2)
                : null,
          ),
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Text(
                _initial,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.dirtyWhite),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.background, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Add a Server" (+) affordance at the foot of the rail's space list.
class _AddServerButton extends StatelessWidget {
  const _AddServerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: Tooltip(
        message: 'Add a server',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.darkGray,
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.add, color: Color(0xFF43B581)),
          ),
        ),
      ),
    );
  }
}
