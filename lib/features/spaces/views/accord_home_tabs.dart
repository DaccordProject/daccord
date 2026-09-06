part of 'accord_home.dart';

/// The browser-style strip of open channel tabs across the top of the content
/// area. Ports the reference client's `main_window_tabs.gd`: tabs open when a
/// channel is selected, can be reordered/closed, carry a right-click menu, and
/// show a space icon when two tabs share a channel name. Hidden when one or zero
/// tabs are open (the reference shows a header spacer in that case).
class _TabStrip extends ConsumerStatefulWidget {
  const _TabStrip({required this.onSelect});

  /// Called when a tab is activated so the host can flip the active server and
  /// mark the channel read.
  final void Function(OpenTab tab) onSelect;

  @override
  ConsumerState<_TabStrip> createState() => _TabStripState();
}

/// Width of the fade drawn over an edge that has tabs scrolled past it.
const double _tabFadeWidth = 20;

class _TabStripState extends ConsumerState<_TabStrip> {
  /// Owned here (rather than by [HorizontalWheelScroll]) so the edge fades can
  /// watch it, and so `ReorderableListView` keeps driving it for drag
  /// auto-scroll.
  final ScrollController _scroll = ScrollController();

  bool _fadeStart = false;
  bool _fadeEnd = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncFades);
  }

  @override
  void dispose() {
    _scroll.removeListener(_syncFades);
    _scroll.dispose();
    super.dispose();
  }

  /// Recomputes which edges have content hidden behind them. Cheap enough to
  /// run on every scroll tick; only rebuilds when a flag actually flips.
  void _syncFades() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final start = position.extentBefore > 0.5;
    final end = position.extentAfter > 0.5;
    if (start == _fadeStart && end == _fadeEnd) return;
    // A position can settle mid-frame (e.g. reorder auto-scroll); never call
    // setState during build/layout.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
      return;
    }
    setState(() {
      _fadeStart = start;
      _fadeEnd = end;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final tabsState = ref.watch(openTabsControllerProvider);
    final tabs = tabsState.tabs;
    if (tabs.length <= 1) return const SizedBox.shrink();

    final connections = ref.watch(connectionsControllerProvider);
    final activeKey = tabsState.activeKey;

    // A space icon is only drawn on tabs whose channel name collides with
    // another open tab (mirrors the reference's `update_icons`).
    final nameCounts = <String, int>{};
    for (final t in tabs) {
      nameCounts[t.name] = (nameCounts[t.name] ?? 0) + 1;
    }

    final list = ReorderableListView.builder(
      scrollController: _scroll,
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      proxyDecorator: (child, index, animation) =>
          Material(color: Colors.transparent, child: child),
      itemCount: tabs.length,
      onReorderItem: (oldIndex, newIndex) => ref
          .read(openTabsControllerProvider.notifier)
          .reorder(oldIndex, newIndex),
      itemBuilder: (context, index) {
        final tab = tabs[index];
        final conn = connections.connectionFor(tab.serverKey);
        final space = conn?.spaces.firstWhereOrNull((s) => s.id == tab.spaceId);
        final iconUrl = (nameCounts[tab.name] ?? 0) > 1 && space != null
            ? accordSpaceIconUrl(space, conn?.session.server.cdnUrl)
            : null;
        return ReorderableDragStartListener(
          key: ValueKey(tab.key),
          index: index,
          child: _TabChip(
            tab: tab,
            active: tab.key == activeKey,
            iconUrl: iconUrl,
            onTap: () => widget.onSelect(tab),
            onClose: () =>
                ref.read(openTabsControllerProvider.notifier).close(tab.key),
            onContextMenu: (pos) =>
                _showTabMenu(context, ref, tab, index, tabs.length, pos),
          ),
        );
      },
    );

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: colors.foreground, width: 1)),
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        // Metrics change without a scroll when tabs open/close or the pane is
        // resized, so refresh the fades then too.
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
            return false;
          },
          child: HorizontalWheelScroll(
            controller: _scroll,
            builder: (context, _) => _withEdgeFades(list),
          ),
        ),
      ),
    );
  }

  /// Fades whichever edges have tabs scrolled past them, so it's visible that
  /// the strip continues off-screen (the scrollbar is hidden here).
  Widget _withEdgeFades(Widget child) {
    if (!_fadeStart && !_fadeEnd) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!width.isFinite || width <= 0) return child;
        final stop = (_tabFadeWidth / width).clamp(0.0, 0.5);
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              _fadeStart ? Colors.transparent : Colors.white,
              Colors.white,
              Colors.white,
              _fadeEnd ? Colors.transparent : Colors.white,
            ],
            stops: [0, stop, 1 - stop, 1],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }

  Future<void> _showTabMenu(
    BuildContext context,
    WidgetRef ref,
    OpenTab tab,
    int index,
    int count,
    Offset globalPos,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPos & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('Copy Link')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'close',
          enabled: count > 1,
          child: const Text('Close'),
        ),
        PopupMenuItem(
          value: 'right',
          enabled: index < count - 1,
          child: const Text('Close to the Right'),
        ),
        PopupMenuItem(
          value: 'others',
          enabled: count > 1,
          child: const Text('Close Others'),
        ),
      ],
    );
    if (selected == null) return;
    final notifier = ref.read(openTabsControllerProvider.notifier);
    switch (selected) {
      case 'copy':
        if (context.mounted) _copyTabLink(context, ref, tab);
      case 'close':
        notifier.close(tab.key);
      case 'right':
        notifier.closeToRight(tab.key);
      case 'others':
        notifier.closeOthers(tab.key);
    }
  }

  void _copyTabLink(BuildContext context, WidgetRef ref, OpenTab tab) {
    final conn = ref
        .read(connectionsControllerProvider)
        .connectionFor(tab.serverKey);
    if (conn == null) return;
    final space = conn.spaces.firstWhereOrNull((s) => s.id == tab.spaceId);
    final url = _buildConnectLink(conn.session.server, space, tab.name);
    Clipboard.setData(ClipboardData(text: url));
    showInfoSnack(context, 'Link copied!');
  }
}

/// Builds a `daccord://connect/<host>[/<slug>][?channel=<name>]` share link,
/// matching the reference client's `UriHandler.build_connect_url`.
String _buildConnectLink(
  AccordServer server,
  AccordSpace? space,
  String channelName,
) {
  var host = server.baseUrl.replaceFirst(RegExp(r'^https?://'), '');
  final slash = host.indexOf('/');
  if (slash != -1) host = host.substring(0, slash);
  final slug = (space?.slug.isNotEmpty ?? false) ? space!.slug : '';
  var url = 'daccord://connect/$host';
  if (slug.isNotEmpty) url += '/${Uri.encodeComponent(slug)}';
  if (channelName.isNotEmpty) {
    url += '?channel=${Uri.encodeComponent(channelName)}';
  }
  return url;
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.active,
    required this.iconUrl,
    required this.onTap,
    required this.onClose,
    required this.onContextMenu,
  });

  final OpenTab tab;
  final bool active;
  final String? iconUrl;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final void Function(Offset globalPos) onContextMenu;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        onTertiaryTapUp: (_) => onClose(),
        onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 180),
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              color: active ? colors.foreground : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: active ? colors.darkGray : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (iconUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: CachedNetworkImage(
                      imageUrl: iconUrl!,
                      width: 16,
                      height: 16,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const SizedBox(width: 16),
                    ),
                  ),
                  const SizedBox(width: 6),
                ] else ...[
                  Icon(Icons.tag, size: 14, color: colors.gray),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    tab.name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: active ? Colors.white : colors.dirtyWhite,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                _TabCloseButton(onTap: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabCloseButton extends StatefulWidget {
  const _TabCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_TabCloseButton> createState() => _TabCloseButtonState();
}

class _TabCloseButtonState extends State<_TabCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? colors.darkGray : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(Icons.close, size: 13, color: colors.dirtyWhite),
        ),
      ),
    );
  }
}
