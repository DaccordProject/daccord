import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the discovery panel: a searchable browser of public spaces the user can
/// join. Backed by the master-server directory. The Accord analogue of the
/// reference client's `discovery_panel`.
Future<void> showAccordDiscovery(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _DiscoveryPanel(),
  );
}

class _DiscoveryPanel extends ConsumerStatefulWidget {
  const _DiscoveryPanel();

  @override
  ConsumerState<_DiscoveryPanel> createState() => _DiscoveryPanelState();
}

class _DiscoveryPanelState extends ConsumerState<_DiscoveryPanel> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>>? _listings;
  final Set<String> _joining = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _listings = null;
      _error = null;
    });
    final result = await client.directory.browse(query: query.trim());
    if (!mounted) return;
    final data = result.data;
    List<dynamic> raw = const [];
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      raw = (data['spaces'] ?? data['results'] ?? data['listings'] ?? const [])
          as List;
    }
    setState(() {
      if (!result.ok) {
        _error = result.error?.toString() ?? 'Failed to load directory';
        _listings = const [];
      } else {
        _listings = raw
            .map<Map<String, dynamic>>((e) =>
                e is Map ? e.cast<String, dynamic>() : <String, dynamic>{})
            .toList();
      }
    });
  }

  Future<void> _join(String spaceId) async {
    final client = _client;
    if (client == null) return;
    setState(() => _joining.add(spaceId));
    final result = await client.spaces.join(spaceId);
    if (!mounted) return;
    setState(() => _joining.remove(spaceId));
    final space = result.data;
    if (result.ok && space is AccordSpace) {
      ref.read(spacesControllerProvider.notifier).upsertSpace(space);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Joined ${space.name}')),
      );
    } else {
      setState(() => _error = result.error?.toString() ?? 'Failed to join');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final listings = _listings;
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
                    child:
                        Text('Discover', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: colors.gray),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _query,
                onChanged: _onChanged,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Search public spaces',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: listings == null
                  ? const Center(child: CircularProgressIndicator())
                  : listings.isEmpty
                      ? Center(
                          child: Text(_error ?? 'No spaces found',
                              style: theme.textTheme.bodyMedium))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: listings.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final listing = listings[index];
                            final id = listing['id']?.toString() ??
                                listing['space_id']?.toString() ??
                                '';
                            final name =
                                listing['name']?.toString() ?? 'Unnamed space';
                            final description =
                                listing['description']?.toString() ?? '';
                            final memberCount = listing['member_count'] ??
                                listing['members'];
                            final joining = _joining.contains(id);
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: colors.darkGray,
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                title: Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  description.isNotEmpty
                                      ? description
                                      : (memberCount != null
                                          ? '$memberCount members'
                                          : ''),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: FilledButton(
                                  onPressed:
                                      joining || id.isEmpty ? null : () => _join(id),
                                  child: joining
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Text('Join'),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
