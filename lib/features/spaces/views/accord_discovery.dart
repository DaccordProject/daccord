import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the discovery panel: a searchable browser of public spaces the user
/// can join. Backed by the **master-server** directory (unauthenticated), so it
/// works before signing in to any instance. The Accord analogue of the
/// reference client's `discovery_panel`.
Future<void> showAccordDiscovery(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _DiscoveryPanel(),
  );
}

class _DiscoveryPanel extends StatelessWidget {
  const _DiscoveryPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.explore, size: 20, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Discover Servers',
                        style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: colors.gray),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AccordDiscoveryBody(
                // Standalone discovery (no Add-Server dialog around it): when a
                // listing needs auth, close this and open the Add-Server flow
                // pre-targeted at the listing's instance + space.
                onJoinRequiresAuth: (serverUrl, spaceId) {
                  Navigator.of(context).pop();
                  showAddServerDialog(context,
                      initialUrl: serverUrl, joinSpaceId: spaceId);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The searchable public-space browser (search box + tag filter + results),
/// reusable both as the standalone discovery dialog and inside the
/// Add-a-Server "Browse" tab.
///
/// Browsing always targets the **master server** (configured in settings,
/// default `https://master.daccord.gg`) and needs no authentication — each
/// listing carries its own `server_url`, so a single directory federates across
/// instances. Joining a listing for an instance you are not connected to needs
/// auth against that instance: [onJoinRequiresAuth] is invoked so the host can
/// drive the right flow (switch the Add-Server URL tab, or open it fresh).
class AccordDiscoveryBody extends ConsumerStatefulWidget {
  const AccordDiscoveryBody({super.key, this.onJoinRequiresAuth});

  /// Called when joining requires authenticating against `serverUrl` first
  /// (i.e. there is no live connection to that instance yet). `spaceId` is the
  /// directory listing's space to join once connected.
  final void Function(String serverUrl, String spaceId)? onJoinRequiresAuth;

  @override
  ConsumerState<AccordDiscoveryBody> createState() =>
      _AccordDiscoveryBodyState();
}

class _AccordDiscoveryBodyState extends ConsumerState<AccordDiscoveryBody> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>>? _listings;
  List<String> _tags = const [];
  String? _activeTag;
  final Set<String> _joining = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  String get _masterUrl =>
      ref.read(settingsControllerProvider).masterServerUrl;

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    setState(() {
      _listings = null;
      _error = null;
    });
    // Unauthenticated client pointed at the master server; only its directory
    // API is used (no gateway / login).
    final client = AccordClient(baseUrl: _masterUrl);
    RestResult result;
    try {
      result = await client.directory.browse(
        query: _query.text.trim(),
        tag: _activeTag ?? '',
      );
    } finally {
      client.rest.close();
    }
    if (!mounted) return;

    final data = result.data;
    List<dynamic> raw = const [];
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      raw = (data['spaces'] ?? data['results'] ?? data['data'] ?? const [])
          as List;
    }

    setState(() {
      if (!result.ok) {
        _error = result.error?.toString() ?? 'Failed to load directory';
        _listings = const [];
        return;
      }
      _listings = raw
          .map<Map<String, dynamic>>((e) =>
              e is Map ? e.cast<String, dynamic>() : <String, dynamic>{})
          .toList();
      // Only refresh the tag bar from an unfiltered result, so filtering by a
      // tag doesn't collapse the bar to that single tag.
      if (_activeTag == null) {
        final tags = <String>{};
        for (final l in _listings!) {
          for (final t in (l['tags'] as List? ?? const [])) {
            final s = t.toString().trim();
            if (s.isNotEmpty) tags.add(s);
          }
        }
        _tags = tags.toList()..sort();
      }
    });
  }

  void _selectTag(String? tag) {
    setState(() => _activeTag = tag);
    _search();
  }

  Future<void> _join(Map<String, dynamic> listing) async {
    final rawServerUrl = listing['server_url']?.toString() ?? '';
    final spaceId =
        listing['space_id']?.toString() ?? listing['id']?.toString() ?? '';
    if (rawServerUrl.isEmpty || spaceId.isEmpty) {
      setState(() => _error = 'This listing is missing its server details');
      return;
    }
    final baseUrl = AccordServer.fromBaseUrl(rawServerUrl).baseUrl;
    final auth = ref.read(accordAuthProvider.notifier);
    final existingKey = auth.keyForBaseUrl(baseUrl);

    // Not connected to this instance yet — defer to the host to authenticate.
    if (existingKey == null) {
      final handler = widget.onJoinRequiresAuth;
      if (handler != null) {
        handler(baseUrl, spaceId);
      } else {
        showAddServerDialog(context,
            initialUrl: baseUrl, joinSpaceId: spaceId);
      }
      return;
    }

    // Already connected: join directly on that connection and switch to it.
    final client = auth.clientForKey(existingKey);
    if (client == null) return;
    setState(() => _joining.add(spaceId));
    final result = await client.spaces.join(spaceId);
    if (!mounted) return;
    setState(() => _joining.remove(spaceId));
    final space = result.data;
    auth.setActiveServer(existingKey);
    if ((result.ok || result.statusCode == 409) && space is AccordSpace) {
      ref.read(spacesControllerProvider.notifier).upsertSpace(space);
    } else if (!result.ok && result.statusCode != 409) {
      setState(() => _error = result.error?.toString() ?? 'Failed to join');
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final listings = _listings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _query,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search servers...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        if (_tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _TagChip(
                  label: 'All',
                  selected: _activeTag == null,
                  onTap: () => _selectTag(null),
                ),
                for (final tag in _tags)
                  _TagChip(
                    label: tag,
                    selected: _activeTag == tag,
                    onTap: () => _selectTag(tag),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: listings == null
              ? const Center(child: CircularProgressIndicator())
              : listings.isEmpty
                  ? Center(
                      child: Text(_error ?? 'No servers found',
                          style: theme.textTheme.bodyMedium),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: listings.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final listing = listings[index];
                        final id = listing['space_id']?.toString() ??
                            listing['id']?.toString() ??
                            '';
                        return _DiscoveryCard(
                          listing: listing,
                          colors: colors,
                          theme: theme,
                          joining: _joining.contains(id),
                          onJoin: () => _join(listing),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.listing,
    required this.colors,
    required this.theme,
    required this.joining,
    required this.onJoin,
  });

  final Map<String, dynamic> listing;
  final BonfireThemeExtension colors;
  final ThemeData theme;
  final bool joining;
  final VoidCallback onJoin;

  /// Prefixes relative icon paths (`/...`) with the listing's own server URL.
  String? get _iconUrl {
    final raw = listing['icon_url']?.toString();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    final server = listing['server_url']?.toString() ?? '';
    if (server.isEmpty) return null;
    final base = AccordServer.normalizeBaseUrl(server);
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
  }

  @override
  Widget build(BuildContext context) {
    final name = listing['name']?.toString() ?? 'Unknown Space';
    final description = listing['description']?.toString() ?? '';
    final memberCount = (listing['member_count'] as num?)?.toInt() ?? 0;
    final presenceCount = (listing['presence_count'] as num?)?.toInt() ?? 0;
    final tags = [
      for (final t in (listing['tags'] as List? ?? const []))
        t.toString().trim(),
    ].where((t) => t.isNotEmpty).toList();
    final iconUrl = _iconUrl;

    final memberLine = StringBuffer('$memberCount members');
    if (presenceCount > 0) memberLine.write(' · $presenceCount online');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: colors.darkGray,
              foregroundImage: iconUrl == null
                  ? null
                  : CachedNetworkImageProvider(iconUrl),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(memberLine.toString(),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.gray)),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final tag in tags.take(4))
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.darkGray,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(tag,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: colors.gray)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: joining ? null : onJoin,
              child: joining
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}
